// Third-party consumer example: imports the selenium-aether-go module and drives
// the protocol. The engine .so is resolved via the module's own bundled native/
// dir (cgo rpath ${SRCDIR}/native) — no SELENIUM_CORE_LIB, and the packaged
// module copy has no core/ sibling, so only the bundled .so can load/link.
//
// Modes (argv[1]):
//   ffi  — no browser: pure engine helpers + a transport-error round-trip.
//   live — real headless Chrome if chromedriver is on PATH; skips otherwise.
package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"net/url"
	"strconv"
	"time"

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

func freePort() int {
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func waitUp(port int) bool {
	end := time.Now().Add(10 * time.Second)
	for time.Now().Before(end) {
		if c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 500*time.Millisecond); err == nil {
			c.Close()
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
}

func modeLive() {
	driver, err := exec.LookPath("chromedriver")
	if err != nil {
		fmt.Println("consumer(live): SKIPPED — chromedriver not on PATH")
		return
	}
	port := freePort()
	cmd := exec.Command(driver, "--port="+strconv.Itoa(port))
	if err := cmd.Start(); err != nil {
		fmt.Println("consumer(live): SKIPPED — could not start chromedriver")
		return
	}
	defer func() { _ = cmd.Process.Kill(); _, _ = cmd.Process.Wait() }()
	if !waitUp(port) {
		fmt.Println("consumer(live): SKIPPED — chromedriver did not come up")
		return
	}
	d, err := selenium.NewChrome("http://127.0.0.1:"+strconv.Itoa(port), selenium.Headless())
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
	el, err := d.FindElement(selenium.ByID, "h")
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
