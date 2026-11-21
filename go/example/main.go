// Third-party consumer example: imports the selenium-aether-go module and drives
// the protocol. The engine .so is resolved via the module's own bundled native/
// dir (cgo rpath ${SRCDIR}/native) — no SELENIUM_CORE_LIB, and the packaged
// module copy has no core/ sibling, so only the bundled .so can load/link.
//
// Modes (argv[1]):
//   ffi  — no browser: pure engine helpers + a transport-error round-trip.
//   live — real headless Chrome through an engine-started driver; skips if none resolves.
package main

import (
	"fmt"
	"os"
	"net/url"

	selenium "github.com/seleniumhq/selenium-aether-go"
)

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "FAIL:", msg)
	os.Exit(1)
}

func modeFFI() {
	if os.Getenv("SELENIUM_CORE_LIB") != "" {
		fail("SELENIUM_CORE_LIB is set; consumer must run without it")
	}
	if selenium.Route("get") != "POST /session/:sessionId/url" {
		fail("Route(get) wrong: " + selenium.Route("get"))
	}
	if selenium.ErrorCode("no such element") != 17 {
		fail("ErrorCode wrong")
	}
	// A transport failure round-trips cleanly (proves execute + the bundled .so).
	if _, err := selenium.NewChrome("http://127.0.0.1:1"); err == nil {
		fail("expected transport failure against dead port")
	}
	fmt.Println("consumer(ffi): OK — bundled module loaded its own .so via cgo rpath")
}

func modeLive() {
	// The engine starts the driver, so the whole tree (browser included) ends
	// on Stop and when this process dies.
	cd, err := selenium.EnsureDriver("chrome", "")
	if err != nil {
		fmt.Println("consumer(live): SKIPPED — the engine cannot resolve a chromedriver")
		return
	}
	defer cd.Stop()
	d, err := selenium.NewChrome(cd.URL(), selenium.Headless())
	if err != nil {
		fail("NewChrome: " + err.Error())
	}
	defer d.Quit()
	html := `<html><head><title>Installed</title></head><body><h1 id="h">Hi</h1></body></html>`
	if err := d.Get("data:text/html;charset=utf-8," + url.PathEscape(html)); err != nil {
		fail("Get: " + err.Error())
	}
	if title, _ := d.Title(); title != "Installed" {
		fail("title = " + title)
	}
	el, err := d.FindElement(selenium.By.Id("h"))
	if err != nil {
		fail("FindElement: " + err.Error())
	}
	if txt, _ := el.Text(); txt != "Hi" {
		fail("text = " + txt)
	}
	fmt.Println("consumer(live): OK — bundled module drove real headless Chrome")
}

func main() {
	os.Unsetenv("SELENIUM_CORE_LIB")
	mode := "ffi"
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	switch mode {
	case "ffi":
		modeFFI()
	case "live":
		modeLive()
	default:
		fail("unknown mode: " + mode)
	}
}
