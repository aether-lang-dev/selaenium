// Live end-to-end test: a real headless Chrome session driven entirely through
// the pure-Aether engine from Go. The whole pipeline —
// Go -> cgo -> libselenium_core.so -> std.http.client -> chromedriver -> Chrome.
// Skips if chromedriver is absent.
package selenium

import (
	"encoding/json"
	"net"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

const liveHTML = `<html><head><title>Aether Selenium</title></head>` +
	`<body><h1 id="hdr">Hello</h1>` +
	`<a href="#" id="lnk" class="nav">click me</a>` +
	`<input id="box" name="q"/></body></html>`

func freePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func waitUp(port int, d time.Duration) bool {
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 500*time.Millisecond)
		if err == nil {
			c.Close()
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
}

func TestLiveChrome(t *testing.T) {
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
	defer func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}()
	if !waitUp(port, 10*time.Second) {
		t.Skip("chromedriver did not come up")
	}

	drv, err := NewChrome("http://127.0.0.1:"+strconv.Itoa(port), Headless())
	if err != nil {
		t.Fatalf("NewChrome: %v", err)
	}
	defer drv.Quit()

	if drv.SessionID() == "" {
		t.Fatal("no session id after newSession")
	}
	t.Logf("session %s...", drv.SessionID()[:8])

	page := "data:text/html;charset=utf-8," + url.PathEscape(liveHTML)
	if err := drv.Get(page); err != nil {
		t.Fatalf("Get: %v", err)
	}

	title, err := drv.Title()
	if err != nil || title != "Aether Selenium" {
		t.Fatalf("Title = %q, err=%v", title, err)
	}

	hdr, err := drv.FindElement(ByID, "hdr")
	if err != nil {
		t.Fatalf("FindElement(ByID): %v", err)
	}
	if txt, _ := hdr.Text(); txt != "Hello" {
		t.Fatalf("hdr.Text = %q", txt)
	}

	lnk, err := drv.FindElement(ByClassName, "nav")
	if err != nil {
		t.Fatalf("FindElement(ByClassName): %v", err)
	}
	if tag, _ := lnk.TagName(); tag != "a" {
		t.Fatalf("lnk.TagName = %q", tag)
	}
	if err := lnk.Click(); err != nil {
		t.Fatalf("Click: %v", err)
	}

	box, err := drv.FindElement(ByCSS, "#box")
	if err != nil {
		t.Fatalf("FindElement(#box): %v", err)
	}
	if err := box.SendKeys("hello world"); err != nil {
		t.Fatalf("SendKeys: %v", err)
	}
	if v, _ := box.GetProperty("value"); v != "hello world" {
		t.Fatalf("box value = %v", v)
	}

	n, err := drv.ExecuteScript("return 40 + 2;")
	if err != nil {
		t.Fatalf("ExecuteScript: %v", err)
	}
	if f, ok := n.(float64); !ok || f != 42 {
		t.Fatalf("script returned %v", n)
	}

	// Negative path: a missing element yields a typed NoSuchElement error.
	if _, err := drv.FindElement(ByID, "does-not-exist"); !IsNoSuchElement(err) {
		t.Fatalf("want NoSuchElement, got %v", err)
	}

	t.Log("live Chrome smoke test green")
}

const liveAtomsHTML = `<html><head><title>Aether Atoms</title></head>` +
	`<body><h1 id="hdr">Header</h1>` +
	`<button id="btn">Go</button>` +
	`<p id="gone" style="display:none">hidden</p>` +
	`<a id="lnk" href="https://example.com/x">link</a></body></html>`

// TestLiveAtoms drives a real Chrome session through the atom-backed commands
// (isDisplayed / getAttribute / relative locators), all run in-page by the
// engine via the aether_sel_embed_* atom C ABI. Mirrors the Python fixture.
func TestLiveAtoms(t *testing.T) {
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
	defer func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}()
	if !waitUp(port, 10*time.Second) {
		t.Skip("chromedriver did not come up")
	}

	drv, err := NewChrome("http://127.0.0.1:"+strconv.Itoa(port), Headless())
	if err != nil {
		t.Fatalf("NewChrome: %v", err)
	}
	defer drv.Quit()

	page := "data:text/html;charset=utf-8," + url.PathEscape(liveAtomsHTML)
	if err := drv.Get(page); err != nil {
		t.Fatalf("Get: %v", err)
	}

	hdr, err := drv.FindElement(ByID, "hdr")
	if err != nil {
		t.Fatalf("FindElement(#hdr): %v", err)
	}
	if shown, err := hdr.IsDisplayed(); err != nil || !shown {
		t.Fatalf("hdr.IsDisplayed = %v, err=%v; want true", shown, err)
	}

	gone, err := drv.FindElement(ByID, "gone")
	if err != nil {
		t.Fatalf("FindElement(#gone): %v", err)
	}
	if shown, err := gone.IsDisplayed(); err != nil || shown {
		t.Fatalf("gone.IsDisplayed = %v, err=%v; want false", shown, err)
	}

	lnk, err := drv.FindElement(ByID, "lnk")
	if err != nil {
		t.Fatalf("FindElement(#lnk): %v", err)
	}
	href, err := lnk.GetAttribute("href")
	if err != nil {
		t.Fatalf("GetAttribute(href): %v", err)
	}
	if !strings.Contains(href, "example.com/x") {
		t.Fatalf("GetAttribute(href) = %q; want to contain example.com/x", href)
	}

	rel, err := drv.FindRelative("button", map[string]interface{}{"kind": "below", "sel": "#hdr"})
	if err != nil {
		t.Fatalf("FindRelative: %v", err)
	}
	if len(rel) < 1 {
		t.Fatalf("FindRelative returned %d elements; want >= 1", len(rel))
	}

	t.Log("live atoms test green")
}

// TestLiveBidi drives a real Chrome session over WebDriver-BiDi end to end:
// subscribe to log.entryAdded, emit a console.log via executeScript, receive the
// event asynchronously, and issue a raw session.status command. Mirrors the
// canonical live BiDi test already passing in Python/Ruby.
func TestLiveBidi(t *testing.T) {
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
	defer func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}()
	if !waitUp(port, 10*time.Second) {
		t.Skip("chromedriver did not come up")
	}

	drv, err := NewChrome("http://127.0.0.1:"+strconv.Itoa(port), Headless())
	if err != nil {
		t.Fatalf("NewChrome: %v", err)
	}
	defer drv.Quit()

	if !drv.BidiAvailable() {
		t.Fatal("BidiAvailable = false; session negotiated no webSocketUrl")
	}

	page := "data:text/html;charset=utf-8," + url.PathEscape(liveHTML)
	if err := drv.Get(page); err != nil {
		t.Fatalf("Get: %v", err)
	}

	bidi, err := drv.Bidi()
	if err != nil {
		t.Fatalf("Bidi: %v", err)
	}

	ack, err := bidi.Subscribe(BidiEvent.LogEntryAdded)
	if err != nil {
		t.Fatalf("Subscribe: %v", err)
	}
	if ack["type"] != "success" {
		t.Fatalf("subscribe ack type = %v, want success", ack["type"])
	}

	if _, err := drv.ExecuteScript("console.log('bidi-hello');"); err != nil {
		t.Fatalf("ExecuteScript: %v", err)
	}

	ev, err := bidi.NextEvent(BidiEvent.LogEntryAdded, 8000)
	if err != nil {
		t.Fatalf("NextEvent: %v", err)
	}
	if ev == nil {
		t.Fatal("NextEvent returned nil (timed out waiting for log.entryAdded)")
	}
	if ev["method"] != BidiEvent.LogEntryAdded {
		t.Fatalf("event method = %v, want %s", ev["method"], BidiEvent.LogEntryAdded)
	}
	evJSON, err := json.Marshal(ev)
	if err != nil {
		t.Fatalf("marshal event: %v", err)
	}
	if !strings.Contains(string(evJSON), "bidi-hello") {
		t.Fatalf("event JSON did not contain logged text: %s", evJSON)
	}

	status, err := bidi.Command("session.status", nil, 10000)
	if err != nil {
		t.Fatalf("Command(session.status): %v", err)
	}
	if status["type"] != "success" {
		t.Fatalf("session.status type = %v, want success", status["type"])
	}

	// Typed convenience commands: getTree -> top context, script.evaluate.
	ctx, err := bidi.TopContext()
	if err != nil {
		t.Fatalf("TopContext: %v", err)
	}
	if ctx == "" {
		t.Fatal("TopContext returned empty context id")
	}

	// script.evaluate a plain expression (JSON numbers -> float64 in Go).
	v, err := bidi.EvaluateValue("6*7")
	if err != nil {
		t.Fatalf("EvaluateValue(6*7): %v", err)
	}
	if f, ok := v.(float64); !ok || f != 42 {
		t.Fatalf("EvaluateValue(6*7) = %v (%T); want 42", v, v)
	}

	// script.evaluate awaits a returned promise — BiDi's richer alternative.
	pv, err := bidi.EvaluateValue("Promise.resolve(41+1)")
	if err != nil {
		t.Fatalf("EvaluateValue(Promise.resolve(41+1)): %v", err)
	}
	if f, ok := pv.(float64); !ok || f != 42 {
		t.Fatalf("EvaluateValue(Promise.resolve(41+1)) = %v (%T); want 42", pv, pv)
	}

	// Network interception: subscribe to beforeRequestSent, add an intercept,
	// trigger a fetch, receive the paused-request event, then continue it.
	if _, err := bidi.Subscribe(BidiEvent.BeforeRequestSent); err != nil {
		t.Fatalf("Subscribe(beforeRequestSent): %v", err)
	}
	ic, err := bidi.AddIntercept("beforeRequestSent", "")
	if err != nil {
		t.Fatalf("AddIntercept: %v", err)
	}
	if ic == "" {
		t.Fatal("AddIntercept returned empty intercept id")
	}
	if _, err := drv.ExecuteScript("fetch('https://example.com/blocked').catch(()=>{});"); err != nil {
		t.Fatalf("ExecuteScript(fetch): %v", err)
	}
	nev, err := bidi.NextEvent(BidiEvent.BeforeRequestSent, 8000)
	if err != nil {
		t.Fatalf("NextEvent(beforeRequestSent): %v", err)
	}
	if nev == nil {
		t.Fatal("NextEvent returned nil (timed out waiting for network.beforeRequestSent)")
	}
	rid := EventRequestID(nev)
	if rid == "" {
		t.Fatalf("EventRequestID returned empty id; event = %v", nev)
	}
	if _, err := bidi.ContinueRequest(rid); err != nil {
		t.Fatalf("ContinueRequest(%s): %v", rid, err)
	}

	// Request mocking: fetch a URL, intercept the paused request, and fulfill it
	// with a MOCK response body (network.provideResponse) — never hitting the
	// network — then confirm the page saw the mocked body.
	if _, err := drv.ExecuteScript("window.__mock='';fetch('https://example.com/api').then(r=>r.text()).then(t=>{window.__mock=t}).catch(()=>{});"); err != nil {
		t.Fatalf("ExecuteScript(fetch mock): %v", err)
	}
	mev, err := bidi.NextEvent(BidiEvent.BeforeRequestSent, 8000)
	if err != nil {
		t.Fatalf("NextEvent(beforeRequestSent, mock): %v", err)
	}
	if mev == nil {
		t.Fatal("NextEvent returned nil (timed out waiting for mock network.beforeRequestSent)")
	}
	rid2 := EventRequestID(mev)
	if rid2 == "" {
		t.Fatalf("EventRequestID returned empty id; event = %v", mev)
	}
	reply, err := bidi.ProvideResponse(rid2, 200, "text/plain", "MOCKED-BODY")
	if err != nil {
		t.Fatalf("ProvideResponse(%s): %v", rid2, err)
	}
	if reply["type"] != "success" {
		t.Fatalf("ProvideResponse reply type = %v, want success; reply = %v", reply["type"], reply)
	}
	var got string
	for i := 0; i < 25; i++ {
		v, err := drv.ExecuteScript("return window.__mock;")
		if err != nil {
			t.Fatalf("ExecuteScript(read mock): %v", err)
		}
		got, _ = v.(string)
		if strings.Contains(got, "MOCKED-BODY") {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
	if !strings.Contains(got, "MOCKED-BODY") {
		t.Fatalf("window.__mock = %q; want to contain MOCKED-BODY", got)
	}

	// Cache control: bypass disables the session HTTP cache, default restores it.
	bypass, err := bidi.SetCacheBehavior("bypass")
	if err != nil {
		t.Fatalf("SetCacheBehavior(bypass): %v", err)
	}
	if bypass["type"] != "success" {
		t.Fatalf("SetCacheBehavior(bypass) type = %v, want success; reply = %v", bypass["type"], bypass)
	}
	restore, err := bidi.SetCacheBehavior("default")
	if err != nil {
		t.Fatalf("SetCacheBehavior(default): %v", err)
	}
	if restore["type"] != "success" {
		t.Fatalf("SetCacheBehavior(default) type = %v, want success; reply = %v", restore["type"], restore)
	}

	// ContinueWithAuth needs an auth-challenging server to exercise live; here we
	// only bind it so the wrapper stays compiled and its signature is covered.
	_ = bidi.ContinueWithAuth

	t.Log("live BiDi test green")
}
