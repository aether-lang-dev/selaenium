// Live surface-coverage test (Go): cookies, navigation history, windows, W3C
// actions, screenshot, and execute_script return shapes against a real headless
// Chrome served by a local httptest server (so cookies/navigation have a real
// http:// origin). Skips if chromedriver is absent.
package selenium

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"strconv"
	"testing"
	"time"
)

func TestLiveSurface(t *testing.T) {
	driverBin, err := exec.LookPath("chromedriver")
	if err != nil {
		t.Skip("chromedriver not on PATH")
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if r.URL.Path == "/two" {
			_, _ = w.Write([]byte(`<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>`))
			return
		}
		_, _ = w.Write([]byte(`<!doctype html><title>Page One</title>` +
			`<h1 id="hdr">One</h1><a id="go" href="/two">to two</a>` +
			`<button id="btn" onclick="document.getElementById('hdr').textContent='clicked'">b</button>`))
	}))
	defer srv.Close()

	port := freePort(t)
	cmd := exec.Command(driverBin, "--port="+strconv.Itoa(port))
	if err := cmd.Start(); err != nil {
		t.Skipf("could not start chromedriver: %v", err)
	}
	defer func() { _ = cmd.Process.Kill(); _, _ = cmd.Process.Wait() }()
	if !waitUp(port, 10*time.Second) {
		t.Skip("chromedriver did not come up")
	}

	d, err := NewChrome("http://127.0.0.1:"+strconv.Itoa(port), Headless())
	if err != nil {
		t.Fatalf("NewChrome: %v", err)
	}
	defer d.Quit()

	if err := d.Get(srv.URL + "/one"); err != nil {
		t.Fatalf("Get: %v", err)
	}
	if title, _ := d.Title(); title != "Page One" {
		t.Fatalf("title = %q", title)
	}

	// navigation history
	go2, _ := d.FindElement(By.Id("go"))
	go2.Click()
	if title, _ := d.Title(); title != "Page Two" {
		t.Fatalf("after click title = %q", title)
	}
	d.Back()
	if title, _ := d.Title(); title != "Page One" {
		t.Fatalf("after back title = %q", title)
	}
	d.Forward()
	if title, _ := d.Title(); title != "Page Two" {
		t.Fatalf("after forward title = %q", title)
	}
	d.Back()

	// cookies
	d.DeleteAllCookies()
	if err := d.AddCookie(map[string]interface{}{"name": "flavor", "value": "mint"}); err != nil {
		t.Fatalf("AddCookie: %v", err)
	}
	c, err := d.Cookie("flavor")
	if err != nil {
		t.Fatalf("Cookie: %v", err)
	}
	if c.Value != "mint" {
		t.Fatalf("cookie value = %v", c.Value)
	}
	if err := d.DeleteCookie("flavor"); err != nil {
		t.Fatalf("DeleteCookie: %v", err)
	}

	// windows
	handles, _ := d.WindowHandles()
	if len(handles) < 1 {
		t.Fatalf("no window handles")
	}
	if _, err := d.SetWindowRect(map[string]interface{}{"width": 900, "height": 650}); err != nil {
		t.Fatalf("SetWindowRect: %v", err)
	}
	rect, _ := d.WindowRect()
	if rect.Width != 900 {
		t.Fatalf("window rect = %v", rect)
	}

	// execute_script shapes
	if v, _ := d.ExecuteScript("return 6*7;"); v.(float64) != 42 {
		t.Fatalf("script scalar = %v", v)
	}
	if v, _ := d.ExecuteScript("return arguments[0]+arguments[1];", 40, 2); v.(float64) != 42 {
		t.Fatalf("script args = %v", v)
	}

	// W3C actions: pointer click on the button.
	btn, _ := d.FindElement(By.Id("btn"))
	rct, _ := btn.Rect()
	cx := int(rct.X + rct.Width/2)
	cy := int(rct.Y + rct.Height/2)
	if err := d.PerformActions([]interface{}{map[string]interface{}{
		"type": "pointer", "id": "mouse", "parameters": map[string]interface{}{"pointerType": "mouse"},
		"actions": []interface{}{
			map[string]interface{}{"type": "pointerMove", "duration": 0, "x": cx, "y": cy},
			map[string]interface{}{"type": "pointerDown", "button": 0},
			map[string]interface{}{"type": "pointerUp", "button": 0},
		},
	}}); err != nil {
		t.Fatalf("PerformActions: %v", err)
	}
	hdr, _ := d.FindElement(By.Id("hdr"))
	if txt, _ := hdr.Text(); txt != "clicked" {
		t.Fatalf("actions click did not fire, hdr=%q", txt)
	}
	d.ClearActions()

	// screenshot -> PNG
	shot, _ := d.ScreenshotBase64()
	raw, err := base64.StdEncoding.DecodeString(shot)
	if err != nil || len(raw) < 8 || string(raw[1:4]) != "PNG" {
		t.Fatalf("screenshot not a PNG (%d bytes)", len(raw))
	}

	t.Logf("live surface: cookies/nav/windows/actions/screenshot/script all green")
}
