// No-browser FFI test: proves the Go binding links libselenium_core.so and
// marshals across cgo correctly, exercising the pure engine helpers. Needs only
// the .so (found via the cgo rpath / bundled go/native), no chromedriver.
package selenium

import (
	"encoding/json"
	"testing"
)

func TestRoute(t *testing.T) {
	if got := Route("get"); got != "POST /session/:sessionId/url" {
		t.Fatalf("Route(get) = %q", got)
	}
	if got := Route("nope"); got != "" {
		t.Fatalf("Route(nope) = %q, want empty", got)
	}
}

func TestErrorCode(t *testing.T) {
	if got := ErrorCode("no such element"); got != 17 {
		t.Fatalf("ErrorCode(no such element) = %d, want 17", got)
	}
	if got := ErrorCode(""); got != 0 {
		t.Fatalf("ErrorCode(\"\") = %d, want 0", got)
	}
}

func TestLocatorCSS(t *testing.T) {
	var m map[string]string
	if err := json.Unmarshal([]byte(Locator(By.CssSelector("div.foo"))), &m); err != nil {
		t.Fatal(err)
	}
	if m["using"] != "css selector" || m["value"] != "div.foo" {
		t.Fatalf("locator = %v", m)
	}
}

func TestLocatorIDRewrite(t *testing.T) {
	var m map[string]string
	if err := json.Unmarshal([]byte(Locator(By.Id("main"))), &m); err != nil {
		t.Fatal(err)
	}
	if m["using"] != "css selector" || m["value"] != `*[id="main"]` {
		t.Fatalf("locator = %v", m)
	}
}

func TestTransportFailure(t *testing.T) {
	// A dead port must surface a transport failure (rc -1), not hang or crash.
	d, err := NewChrome("http://127.0.0.1:1")
	if err == nil {
		d.Quit()
		t.Fatal("expected transport failure against dead port")
	}
	e, ok := err.(*Error)
	if !ok || e.Code != -1 {
		t.Fatalf("want transport *Error(-1), got %T %v", err, err)
	}
}
