// Live end-to-end test: a real headless Chrome session driven entirely through
// the pure-Aether engine from Go. The whole pipeline —
// Go -> cgo -> libselenium_core.so -> std.http.client -> chromedriver -> Chrome.
// Skips if chromedriver is absent.
package selenium

import (
	"net"
	"net/url"
	"os/exec"
	"strconv"
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

