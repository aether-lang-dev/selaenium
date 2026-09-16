// Live end-to-end test for the runner surface: the one-line shell, the
// run/step/continue controller, and Selenium IDE .side playback — all driven
// against a real headless Chrome through the pure-Aether engine. Mirrors the D
// binding's live runner tests (d/tests/live_test.d). Skips if chromedriver is
// absent, exactly like the other live tests.
package selenium

import (
	"os/exec"
	"strconv"
	"testing"
	"time"
)

// startChrome spins up a chromedriver + headless Chrome session for a runner
// test, or skips cleanly when chromedriver is absent. It returns the session and
// a cleanup func (the caller defers the cleanup).
func startChrome(t *testing.T) (*WebDriver, func()) {
	t.Helper()
	driverBin, err := exec.LookPath("chromedriver")
	if err != nil {
		t.Skip("chromedriver not on PATH")
	}
	port := freePort(t)
	cmd := exec.Command(driverBin, "--port="+strconv.Itoa(port))
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		t.Skipf("could not start chromedriver: %v", err)
	}
	stopDriver := func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}
	if !waitUp(port, 10*time.Second) {
		stopDriver()
		t.Skip("chromedriver did not come up")
	}
	drv, err := NewChrome("http://127.0.0.1:"+strconv.Itoa(port), Headless())
	if err != nil {
		stopDriver()
		t.Fatalf("NewChrome: %v", err)
	}
	return drv, func() {
		_ = drv.Quit()
		stopDriver()
	}
}

// asObj coerces a decoded-JSON value to a map, failing the test otherwise.
func asObj(t *testing.T, v interface{}, ctx string) map[string]interface{} {
	t.Helper()
	m, ok := v.(map[string]interface{})
	if !ok {
		t.Fatalf("%s: expected a JSON object, got %T: %v", ctx, v, v)
	}
	return m
}

// TestLiveRunnerShell drives the session through the engine-side shell language
// (shell_eval): open a data: page, then read its title and an element's text
// back through the shell. Mirrors the D "shell:" checks.
func TestLiveRunnerShell(t *testing.T) {
	drv, cleanup := startChrome(t)
	defer cleanup()

	ro, err := drv.Shell("open data:text/html,<title>Sh</title><h1 id=q>hey</h1>")
	if err != nil {
		t.Fatalf("Shell(open): %v", err)
	}
	if ok, _ := asObj(t, ro, "shell open")["ok"].(bool); !ok {
		t.Fatalf("shell open: ok != true; got %v", ro)
	}

	title, err := drv.Shell("title")
	if err != nil {
		t.Fatalf("Shell(title): %v", err)
	}
	if v, _ := asObj(t, title, "shell title")["value"].(string); v != "Sh" {
		t.Fatalf("shell title value = %q; want Sh", v)
	}

	txt, err := drv.Shell("text #q")
	if err != nil {
		t.Fatalf("Shell(text #q): %v", err)
	}
	if v, _ := asObj(t, txt, "shell text")["value"].(string); v != "hey" {
		t.Fatalf("shell text #q value = %q; want hey", v)
	}

	t.Log("live runner shell test green")
}

// TestLiveRunnerController exercises the run/step/continue controller: in run
// mode eval executes immediately and emits a command-finished event; in step
// mode eval queues and step runs the queued line. Mirrors the D "runner:" checks.
func TestLiveRunnerController(t *testing.T) {
	drv, cleanup := startChrome(t)
	defer cleanup()

	r := drv.Runner()
	defer r.Close()

	// Run mode: eval executes immediately, reply carries the shell result.
	rr, err := r.Eval("open data:text/html,<title>Run</title><h1 id=z>go</h1>")
	if err != nil {
		t.Fatalf("Eval(open): %v", err)
	}
	res := asObj(t, asObj(t, rr, "run-mode eval reply")["result"], "run-mode eval result")
	if ok, _ := res["ok"].(bool); !ok {
		t.Fatalf("run-mode eval: result.ok != true; got %v", rr)
	}

	tr, err := r.Eval("title")
	if err != nil {
		t.Fatalf("Eval(title): %v", err)
	}
	tres := asObj(t, asObj(t, tr, "title reply")["result"], "title result")
	if v, _ := tres["value"].(string); v != "Run" {
		t.Fatalf("runner title value = %q; want Run", v)
	}

	// A command-finished event fired.
	sawFinished := false
	for {
		ev, err := r.NextEvent()
		if err != nil {
			t.Fatalf("NextEvent: %v", err)
		}
		if ev == nil {
			break
		}
		if m, ok := ev.(map[string]interface{}); ok {
			if method, _ := m["method"].(string); method == "command-finished" {
				sawFinished = true
			}
		}
	}
	if !sawFinished {
		t.Fatal("runner: no command-finished event emitted")
	}

	// Step mode: mode step -> eval queues -> step runs it.
	mr, err := r.Mode("step")
	if err != nil {
		t.Fatalf("Mode(step): %v", err)
	}
	mres := asObj(t, asObj(t, mr, "mode reply")["result"], "mode result")
	if v, _ := mres["mode"].(string); v != "step" {
		t.Fatalf("runner mode = %q; want step", v)
	}

	q, err := r.Eval("text #z")
	if err != nil {
		t.Fatalf("Eval(text #z): %v", err)
	}
	qres := asObj(t, asObj(t, q, "queued reply")["result"], "queued result")
	if _, ok := qres["queued"]; !ok {
		t.Fatalf("step-mode eval: expected a queued reply; got %v", q)
	}

	st, err := r.Step()
	if err != nil {
		t.Fatalf("Step: %v", err)
	}
	stres := asObj(t, asObj(t, st, "step reply")["result"], "step result")
	if stepped, _ := stres["stepped"].(bool); !stepped {
		t.Fatalf("step: stepped != true; got %v", st)
	}
	inner := asObj(t, stres["result"], "step inner result")
	if v, _ := inner["value"].(string); v != "go" {
		t.Fatalf("step ran the queued line -> value %q; want go", v)
	}

	t.Log("live runner controller test green")
}

// TestLiveRunnerPlaySide plays a real Selenium IDE .side project against the
// session and checks the report: one test, one pass, no failures. Mirrors the D
// ".side playback" check.
func TestLiveRunnerPlaySide(t *testing.T) {
	drv, cleanup := startChrome(t)
	defer cleanup()

	const side = `{"name":"d","tests":[{"name":"t","commands":[` +
		`{"command":"open","target":"data:text/html,<title>SideOK</title><h1 id=z>hi</h1>","value":""},` +
		`{"command":"assertTitle","target":"","value":"SideOK"},` +
		`{"command":"assertText","target":"id=z","value":"hi"}]}]}`

	rep, err := drv.PlaySide(side)
	if err != nil {
		t.Fatalf("PlaySide: %v", err)
	}
	m := asObj(t, rep, "side report")
	passed, _ := m["passed"].(float64)
	failed, _ := m["failed"].(float64)
	if passed != 1 {
		t.Fatalf("side report passed = %v; want 1 (report = %v)", m["passed"], m)
	}
	if failed != 0 {
		t.Fatalf("side report failed = %v; want 0 (report = %v)", m["failed"], m)
	}

	t.Log("live runner .side playback test green")
}

// Compile-surface checks that the runner-surface entry points exist and are
// callable (Bridge/RunnerServer are exercised for construction; the full
// injection/serve loops need a driving front-end / socket peer, covered live in
// the D binding). Never invoked.
var (
	_ = (*WebDriver).Bridge
	_ = (*WebDriver).ServeRunner
	_ = NewRunnerServer
	_ = (*Bridge).Inject
	_ = (*Bridge).Pump
	_ = (*Bridge).Serve
	_ = (*RunnerServer).URL
	_ = (*RunnerServer).WSURL
	_ = (*RunnerServer).Port
	_ = (*Runner).Continue
	_ = (*Runner).Inspect
)
