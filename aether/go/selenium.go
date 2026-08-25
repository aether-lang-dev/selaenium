// Package selenium is a Go WebDriver binding re-glued to the shared pure-Aether
// WebDriver core. Since this is the one-engine-many-bindings layout (the same
// shape as servirtium-vcr and html-sanitizer), the entire W3C protocol — command
// catalog, the command→(method,path) route table, path templating, By/locator
// normalization, W3C error decode, and the HTTP round-trip to the driver/Grid —
// lives in and is maintained as the in-repo Aether engine (core/selenium_core.ae),
// exposed via the aether_sel_embed_* C ABI (core/embed.ae). This package does NOT
// reimplement any Selenium protocol logic in Go; it opens a session, issues
// commands by name with JSON params, and marshals results.
//
//	drv, err := selenium.NewChrome("http://127.0.0.1:9515", selenium.Headless())
//	if err != nil { log.Fatal(err) }
//	defer drv.Quit()
//	drv.Get("https://example.com")
//	title, _ := drv.Title()
//	el, _ := drv.FindElement(selenium.ByCSS, "a")
//	el.Click()
package selenium

/*
// Link against the engine .so from two locations, so both the in-repo build
// (this module sitting next to core/) and a bundled consumer copy work.
// ${SRCDIR} expands to this package's real dir at build time, so the rpath
// self-locates; a -L/-rpath to a non-existent dir is harmless.
#cgo LDFLAGS: -L${SRCDIR}/../core/native -L${SRCDIR}/native -lselenium_core -Wl,-rpath,${SRCDIR}/../core/native -Wl,-rpath,${SRCDIR}/native

#include <stdlib.h>

void*  aether_sel_embed_open(const char* base_url);
void   aether_sel_embed_close(void* h);
int    aether_sel_embed_execute(void* h, const char* name, const char* params_json);
char*  aether_sel_embed_last_value(void* h);
int    aether_sel_embed_last_status(void* h);
int    aether_sel_embed_last_error_code(void* h);
char*  aether_sel_embed_last_error(void* h);
char*  aether_sel_embed_session_id(void* h);
char*  aether_sel_embed_by_locator(const char* strategy, const char* value);
char*  aether_sel_embed_route(const char* name);
char*  aether_sel_embed_build_request(const char* name, const char* session_id, const char* params_json);
int    aether_sel_embed_error_code(const char* w3c_error);
void   aether_sel_embed_free_string(char* s);
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"unsafe"
)

// The W3C element-reference key: a findElement result is
// {"element-6066-11e4-a52e-4f735466cecf": "<id>"}.
const w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"

// By strategies. Values match the engine's by_locator strategy strings;
// ByID/ByName/ByClassName are rewritten to CSS in the engine.
type By string

const (
	ByID              By = "id"
	ByName            By = "name"
	ByCSS             By = "css selector"
	ByClassName       By = "className"
	ByTagName         By = "tag name"
	ByLinkText        By = "link text"
	ByPartialLinkText By = "partial link text"
	ByXPath           By = "xpath"
)

// ---- string ownership ------------------------------------------------------

// takeString marshals a caller-owned native char* into a Go string and frees
// it via aether_sel_embed_free_string, per the ABI's ownership rule.
func takeString(ptr *C.char) string {
	if ptr == nil {
		return ""
	}
	defer C.aether_sel_embed_free_string(ptr)
	return C.GoString(ptr)
}

func cstr(s string) *C.char { return C.CString(s) }

// ---- error taxonomy --------------------------------------------------------

// Error is a WebDriver protocol error carrying the engine's stable W3C error
// code (0 = success, -1 = transport failure). Use errors.Is against the
// Err* sentinels or compare Code.
type Error struct {
	Code    int
	Message string
}

func (e *Error) Error() string { return e.Message }

// Sentinel codes for the common cases (match core/selenium_core.ae error_code()).
const (
	codeNoSuchElement          = 17
	codeStaleElementReference  = 23
	codeUnknownCommand         = 28
	codeElementClickIntercept  = 3
	codeElementNotInteractable = 4
	codeInvalidSelector        = 11
	codeTimeout                = 24
	codeTransport              = -1
)

// IsNoSuchElement reports whether err is a "no such element" WebDriver error.
func IsNoSuchElement(err error) bool { return codeIs(err, codeNoSuchElement) }

// IsStaleElement reports whether err is a "stale element reference" error.
func IsStaleElement(err error) bool { return codeIs(err, codeStaleElementReference) }

func codeIs(err error, code int) bool {
	if e, ok := err.(*Error); ok {
		return e.Code == code
	}
	return false
}

// ---- WebDriver -------------------------------------------------------------

// WebDriver is a live (or nascent) WebDriver session over the shared engine.
type WebDriver struct {
	h unsafe.Pointer
}

// Option configures the capabilities used to create a session.
type Option func(caps map[string]interface{})

// Headless adds the standard headless-Chrome launch args.
func Headless() Option {
	return func(caps map[string]interface{}) {
		caps["goog:chromeOptions"] = map[string]interface{}{
			"args": []string{"--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"},
		}
	}
}

// Capability sets an arbitrary top-level capability (e.g. a vendor options map).
func Capability(key string, value interface{}) Option {
	return func(caps map[string]interface{}) { caps[key] = value }
}

// NewChrome starts a Chrome session against a running chromedriver (or Grid).
func NewChrome(commandExecutor string, opts ...Option) (*WebDriver, error) {
	caps := map[string]interface{}{"browserName": "chrome"}
	for _, o := range opts {
		o(caps)
	}
	return NewRemote(commandExecutor, caps)
}

// NewRemote starts a session against an arbitrary remote end with explicit caps.
func NewRemote(commandExecutor string, capabilities map[string]interface{}) (*WebDriver, error) {
	cURL := cstr(commandExecutor)
	defer C.free(unsafe.Pointer(cURL))
	h := C.aether_sel_embed_open(cURL)
	if h == nil {
		return nil, &Error{Code: -1, Message: "failed to open session handle"}
	}
	d := &WebDriver{h: unsafe.Pointer(h)}
	payload := map[string]interface{}{
		"capabilities": map[string]interface{}{"alwaysMatch": capabilities},
	}
	if _, err := d.execute("newSession", payload); err != nil {
		d.closeHandle()
		return nil, err
	}
	return d, nil
}

// execute is the FFI seam: one command by name with JSON params. Returns the
// decoded `value` payload (as a generic Go value) or a typed *Error.
func (d *WebDriver) execute(command string, params map[string]interface{}) (interface{}, error) {
	if params == nil {
		params = map[string]interface{}{}
	}
	pj, err := json.Marshal(params)
	if err != nil {
		return nil, fmt.Errorf("marshal params: %w", err)
	}
	cName := cstr(command)
	cParams := cstr(string(pj))
	rc := int(C.aether_sel_embed_execute(d.h, cName, cParams))
	C.free(unsafe.Pointer(cName))
	C.free(unsafe.Pointer(cParams))
	if rc != 0 {
		code := int(C.aether_sel_embed_last_error_code(d.h))
		msg := takeString(C.aether_sel_embed_last_error(d.h))
		if rc == -1 && code == 0 {
			return nil, &Error{Code: -1, Message: nonEmpty(msg, "transport failure")}
		}
		return nil, &Error{Code: code, Message: msg}
	}
	raw := takeString(C.aether_sel_embed_last_value(d.h))
	if raw == "" {
		return nil, nil
	}
	var v interface{}
	if err := json.Unmarshal([]byte(raw), &v); err != nil {
		return nil, fmt.Errorf("unmarshal value: %w", err)
	}
	return v, nil
}

func nonEmpty(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

// decodeBy asks the engine for the {"using","value"} locator (sharing the ONE
// By-normalization + CSS-escape path with every other binding).
func decodeBy(by By, value string) map[string]interface{} {
	cs := cstr(string(by))
	cv := cstr(value)
	raw := takeString(C.aether_sel_embed_by_locator(cs, cv))
	C.free(unsafe.Pointer(cs))
	C.free(unsafe.Pointer(cv))
	var m map[string]interface{}
	_ = json.Unmarshal([]byte(raw), &m)
	return m
}

// ---- navigation ----

func (d *WebDriver) Get(url string) error {
	_, err := d.execute("get", map[string]interface{}{"url": url})
	return err
}

func (d *WebDriver) CurrentURL() (string, error) { return d.strCmd("getCurrentUrl", nil) }
func (d *WebDriver) Title() (string, error)      { return d.strCmd("getTitle", nil) }
func (d *WebDriver) PageSource() (string, error) { return d.strCmd("getPageSource", nil) }

func (d *WebDriver) Back() error    { _, err := d.execute("goBack", nil); return err }
func (d *WebDriver) Forward() error { _, err := d.execute("goForward", nil); return err }
func (d *WebDriver) Refresh() error { _, err := d.execute("refresh", nil); return err }

// ---- elements ----

func (d *WebDriver) FindElement(by By, value string) (*WebElement, error) {
	v, err := d.execute("findElement", decodeBy(by, value))
	if err != nil {
		return nil, err
	}
	id, err := elementID(v)
	if err != nil {
		return nil, err
	}
	return &WebElement{driver: d, id: id}, nil
}

func (d *WebDriver) FindElements(by By, value string) ([]*WebElement, error) {
	v, err := d.execute("findElements", decodeBy(by, value))
	if err != nil {
		return nil, err
	}
	return elementList(d, v)
}

// ---- script ----

func (d *WebDriver) ExecuteScript(script string, args ...interface{}) (interface{}, error) {
	if args == nil {
		args = []interface{}{}
	}
	return d.execute("executeScript", map[string]interface{}{"script": script, "args": args})
}

// ---- windows ----

func (d *WebDriver) WindowHandles() ([]string, error) {
	v, err := d.execute("getWindowHandles", nil)
	if err != nil {
		return nil, err
	}
	return toStringSlice(v), nil
}

func (d *WebDriver) MaximizeWindow() error   { _, err := d.execute("maximizeWindow", nil); return err }
func (d *WebDriver) MinimizeWindow() error   { _, err := d.execute("minimizeWindow", nil); return err }
func (d *WebDriver) FullscreenWindow() error { _, err := d.execute("fullscreenWindow", nil); return err }

// ---- cookies ----

func (d *WebDriver) AddCookie(cookie map[string]interface{}) error {
	_, err := d.execute("addCookie", map[string]interface{}{"cookie": cookie})
	return err
}

func (d *WebDriver) Cookies() (interface{}, error) { return d.execute("getCookies", nil) }

func (d *WebDriver) Cookie(name string) (interface{}, error) {
	return d.execute("getCookie", map[string]interface{}{"name": name})
}

func (d *WebDriver) DeleteCookie(name string) error {
	_, err := d.execute("deleteCookie", map[string]interface{}{"name": name})
	return err
}

func (d *WebDriver) DeleteAllCookies() error {
	_, err := d.execute("deleteAllCookies", nil)
	return err
}

// CurrentWindowHandle returns the handle of the focused window.
func (d *WebDriver) CurrentWindowHandle() (string, error) {
	return d.strCmd("getCurrentWindowHandle", nil)
}

// SetWindowRect sets the window position/size (nil fields are omitted).
func (d *WebDriver) SetWindowRect(rect map[string]interface{}) (interface{}, error) {
	return d.execute("setWindowRect", rect)
}

// WindowRect returns the current window position/size.
func (d *WebDriver) WindowRect() (interface{}, error) {
	return d.execute("getWindowRect", nil)
}

// PerformActions issues a raw W3C actions sequence (the {"actions":[...]} body).
func (d *WebDriver) PerformActions(actions []interface{}) error {
	_, err := d.execute("actions", map[string]interface{}{"actions": actions})
	return err
}

// ClearActions releases all input state.
func (d *WebDriver) ClearActions() error {
	_, err := d.execute("clearActions", nil)
	return err
}

// ---- screenshots ----

func (d *WebDriver) ScreenshotBase64() (string, error) { return d.strCmd("screenshot", nil) }

// ---- lifecycle ----

func (d *WebDriver) SessionID() string {
	return takeString(C.aether_sel_embed_session_id(d.h))
}

// Quit ends the browser session and releases the handle.
func (d *WebDriver) Quit() error {
	_, err := d.execute("quit", nil)
	d.closeHandle()
	return err
}

func (d *WebDriver) closeHandle() {
	if d.h != nil {
		C.aether_sel_embed_close(d.h)
		d.h = nil
	}
}

// strCmd runs a command whose success value is a string.
func (d *WebDriver) strCmd(command string, params map[string]interface{}) (string, error) {
	v, err := d.execute(command, params)
	if err != nil {
		return "", err
	}
	s, _ := v.(string)
	return s, nil
}

// ---- WebElement ------------------------------------------------------------

// WebElement is a remote element handle. Its methods issue element-scoped
// commands, passing this element's id as the :id path parameter (the engine
// separates path params from the body).
type WebElement struct {
	driver *WebDriver
	id     string
}

func (e *WebElement) ID() string { return e.id }

func (e *WebElement) exec(command string, params map[string]interface{}) (interface{}, error) {
	if params == nil {
		params = map[string]interface{}{}
	}
	params["id"] = e.id
	return e.driver.execute(command, params)
}

func (e *WebElement) Click() error { _, err := e.exec("clickElement", nil); return err }
func (e *WebElement) Clear() error { _, err := e.exec("clearElement", nil); return err }

func (e *WebElement) SendKeys(text string) error {
	chars := make([]interface{}, 0, len(text))
	for _, r := range text {
		chars = append(chars, string(r))
	}
	_, err := e.exec("sendKeysToElement", map[string]interface{}{"text": text, "value": chars})
	return err
}

func (e *WebElement) Text() (string, error) {
	v, err := e.exec("getElementText", nil)
	if err != nil {
		return "", err
	}
	s, _ := v.(string)
	return s, nil
}

func (e *WebElement) TagName() (string, error) {
	v, err := e.exec("getElementTagName", nil)
	if err != nil {
		return "", err
	}
	s, _ := v.(string)
	return s, nil
}

func (e *WebElement) GetAttribute(name string) (interface{}, error) {
	return e.exec("getDomAttribute", map[string]interface{}{"name": name})
}

func (e *WebElement) GetProperty(name string) (interface{}, error) {
	return e.exec("getElementProperty", map[string]interface{}{"name": name})
}

// Rect returns the element's bounding rectangle ({x,y,width,height}).
func (e *WebElement) Rect() (map[string]interface{}, error) {
	v, err := e.exec("getElementRect", nil)
	if err != nil {
		return nil, err
	}
	m, _ := v.(map[string]interface{})
	return m, nil
}

func (e *WebElement) IsEnabled() (bool, error) {
	v, err := e.exec("isElementEnabled", nil)
	if err != nil {
		return false, err
	}
	b, _ := v.(bool)
	return b, nil
}

func (e *WebElement) IsSelected() (bool, error) {
	v, err := e.exec("isElementSelected", nil)
	if err != nil {
		return false, err
	}
	b, _ := v.(bool)
	return b, nil
}

// ---- pure engine helpers (no session needed) ----

// Route returns the "METHOD PATH" route for a command name, or "" if unknown.
// Shares the ONE protocol mapping with every other binding.
func Route(command string) string {
	c := cstr(command)
	defer C.free(unsafe.Pointer(c))
	return takeString(C.aether_sel_embed_route(c))
}

// ErrorCode maps a W3C error string to its stable integer code (0 = success).
func ErrorCode(w3cError string) int {
	c := cstr(w3cError)
	defer C.free(unsafe.Pointer(c))
	return int(C.aether_sel_embed_error_code(c))
}

// Locator returns the W3C {"using","value"} JSON for a (by, value) pair, with
// id/name/className rewritten to CSS exactly as every binding shares.
func Locator(by By, value string) string {
	cs := cstr(string(by))
	cv := cstr(value)
	defer C.free(unsafe.Pointer(cs))
	defer C.free(unsafe.Pointer(cv))
	return takeString(C.aether_sel_embed_by_locator(cs, cv))
}

// ---- result decoding helpers ----

func elementID(v interface{}) (string, error) {
	m, ok := v.(map[string]interface{})
	if !ok {
		return "", &Error{Code: codeNoSuchElement, Message: "element response was not an object"}
	}
	id, ok := m[w3cElementKey].(string)
	if !ok {
		return "", &Error{Code: codeNoSuchElement, Message: "element reference key missing"}
	}
	return id, nil
}

func elementList(d *WebDriver, v interface{}) ([]*WebElement, error) {
	arr, ok := v.([]interface{})
	if !ok {
		return nil, &Error{Code: 1, Message: "elements response was not an array"}
	}
	out := make([]*WebElement, 0, len(arr))
	for _, item := range arr {
		id, err := elementID(item)
		if err != nil {
			return nil, err
		}
		out = append(out, &WebElement{driver: d, id: id})
	}
	return out, nil
}

func toStringSlice(v interface{}) []string {
	arr, _ := v.([]interface{})
	out := make([]string, 0, len(arr))
	for _, item := range arr {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}
