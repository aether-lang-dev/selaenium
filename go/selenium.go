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
#cgo LDFLAGS: -L${SRCDIR}/../selenium_core/native -L${SRCDIR}/native -lselenium_core -Wl,-rpath,${SRCDIR}/../selenium_core/native -Wl,-rpath,${SRCDIR}/native

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

// ---- atom-backed commands (a shared JS atom run in-page via the engine) ----
int    aether_sel_embed_execute_atom(void* h, const char* atom, const char* elem_id, const char* extra_json);
int    aether_sel_embed_is_displayed(void* h, const char* elem_id);
int    aether_sel_embed_get_attribute(void* h, const char* elem_id, const char* name);
char*  aether_sel_embed_atom_str_arg(const char* s);
int    aether_sel_embed_find_relative(void* h, const char* base_css, const char* filters_json);

// ---- WebDriver-BiDi (over the session's negotiated webSocketUrl) ----
// An opaque BiDi channel handle, independent of the W3C session handle.
void*  aether_sel_embed_bidi_open(const char* ws_url);
void   aether_sel_embed_bidi_close(void* h);
int    aether_sel_embed_bidi_send(void* h, int id, const char* method, const char* params_json);
int    aether_sel_embed_bidi_pump(void* h, int timeout_ms);
int    aether_sel_embed_bidi_fd(void* h);
char*  aether_sel_embed_bidi_poll_reply(void* h, int id);
char*  aether_sel_embed_bidi_poll_event(void* h);
int    aether_sel_embed_bidi_lost_events(void* h);
void   aether_sel_embed_bidi_cancel(void* h, int id);
char*  aether_sel_embed_bidi_subscribe(void* h, int id, const char* events_csv, int timeout_ms);
char*  aether_sel_embed_bidi_unsubscribe(void* h, int id, const char* events_csv, int timeout_ms);
char*  aether_sel_embed_bidi_wait_event(void* h, const char* method, int timeout_ms);

// ---- typed BiDi convenience commands (each returns a BiDi reply JSON) ----
char*  aether_sel_embed_bidi_get_tree(void* h, int id, int timeout_ms);
char*  aether_sel_embed_bidi_script_evaluate(void* h, int id, const char* expr, const char* context_id, int timeout_ms);
char*  aether_sel_embed_bidi_navigate(void* h, int id, const char* context_id, const char* url, int timeout_ms);

// ---- BiDi network interception (observe / release / block requests) ----
char*  aether_sel_embed_bidi_network_add_intercept(void* h, int id, const char* phases_csv, const char* url_pattern, int timeout_ms);
char*  aether_sel_embed_bidi_network_remove_intercept(void* h, int id, const char* intercept_id, int timeout_ms);
char*  aether_sel_embed_bidi_network_continue_request(void* h, int id, const char* request_id, int timeout_ms);
char*  aether_sel_embed_bidi_network_fail_request(void* h, int id, const char* request_id, int timeout_ms);
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"strings"
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
	// wsURL is the session's negotiated BiDi endpoint (value.capabilities.webSocketUrl),
	// captured at newSession. Empty if the remote end granted no BiDi channel.
	wsURL string
	// bidi is the BiDi channel, opened lazily on first use so a classic script
	// never opens the WebSocket.
	bidi *BiDi
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
	// Request a BiDi channel so Bidi() is available on demand; the WebSocket
	// itself opens lazily (a classic script never opens it).
	caps := make(map[string]interface{}, len(capabilities)+1)
	for k, v := range capabilities {
		caps[k] = v
	}
	caps["webSocketUrl"] = true
	payload := map[string]interface{}{
		"capabilities": map[string]interface{}{"alwaysMatch": caps},
	}
	v, err := d.execute("newSession", payload)
	if err != nil {
		d.closeHandle()
		return nil, err
	}
	// value.capabilities.webSocketUrl — the BiDi endpoint for this session.
	if m, ok := v.(map[string]interface{}); ok {
		if c, ok := m["capabilities"].(map[string]interface{}); ok {
			if u, ok := c["webSocketUrl"].(string); ok {
				d.wsURL = u
			}
		}
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

// ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

// atomResult drains last_value after an atom cgo call, returning the decoded
// value or a typed *Error — reusing the exact last_value/error machinery of
// execute so atom calls share one error taxonomy with every command.
func (d *WebDriver) atomResult(rc int) (interface{}, error) {
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
		return nil, fmt.Errorf("unmarshal atom value: %w", err)
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

// FindRelative resolves relative locators: elements matching baseCSS filtered by
// spatial relation to anchors, nearest first. Each filter is a map
// {"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"} ("near" also
// accepts "dist"). The atom runs in-page via the engine; the returned array of
// W3C element refs is parsed into WebElement handles.
func (d *WebDriver) FindRelative(baseCSS string, filters ...map[string]interface{}) ([]*WebElement, error) {
	if filters == nil {
		filters = []map[string]interface{}{}
	}
	fj, err := json.Marshal(filters)
	if err != nil {
		return nil, fmt.Errorf("marshal filters: %w", err)
	}
	cBase := cstr(baseCSS)
	cFilters := cstr(string(fj))
	rc := int(C.aether_sel_embed_find_relative(d.h, cBase, cFilters))
	C.free(unsafe.Pointer(cBase))
	C.free(unsafe.Pointer(cFilters))
	v, err := d.atomResult(rc)
	if err != nil {
		return nil, err
	}
	if v == nil {
		return []*WebElement{}, nil
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

// ---- WebDriver-BiDi ----

// BidiAvailable reports whether this session negotiated a webSocketUrl and can
// therefore use BiDi.
func (d *WebDriver) BidiAvailable() bool { return d.wsURL != "" }

// Bidi returns the event-driven BiDi surface for this session, opened lazily
// over the negotiated webSocketUrl. It returns an error if the remote end
// granted no BiDi URL or the channel fails to open.
//
//	bidi, _ := drv.Bidi()
//	bidi.Subscribe(selenium.BidiEvent.LogEntryAdded)
//	drv.Get(url)
//	ev, _ := bidi.NextEvent(selenium.BidiEvent.LogEntryAdded, 5000)
func (d *WebDriver) Bidi() (*BiDi, error) {
	if d.bidi != nil {
		return d.bidi, nil
	}
	if d.wsURL == "" {
		return nil, &Error{Code: 0, Message: "BiDi not available: the session negotiated no webSocketUrl"}
	}
	cURL := cstr(d.wsURL)
	defer C.free(unsafe.Pointer(cURL))
	h := C.aether_sel_embed_bidi_open(cURL)
	if h == nil {
		return nil, &Error{Code: -1, Message: "BiDi channel failed to open"}
	}
	d.bidi = &BiDi{h: unsafe.Pointer(h), nextID: 1}
	return d.bidi, nil
}

// Quit ends the browser session and releases the handle.
func (d *WebDriver) Quit() error {
	if d.bidi != nil {
		d.bidi.Close()
		d.bidi = nil
	}
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

// IsDisplayed reports whether the element is shown (the isDisplayed atom, run
// in-page by the engine — the visibility algorithm, not a naive style check).
func (e *WebElement) IsDisplayed() (bool, error) {
	cid := cstr(e.id)
	rc := int(C.aether_sel_embed_is_displayed(e.driver.h, cid))
	C.free(unsafe.Pointer(cid))
	v, err := e.driver.atomResult(rc)
	if err != nil {
		return false, err
	}
	b, _ := v.(bool)
	return b, nil
}

// GetAttribute is the classic getAttribute(name): property-or-attribute
// (boolean attrs, live properties like value/checked), via the shared engine
// atom. Use GetDomAttribute for the raw W3C DOM attribute.
func (e *WebElement) GetAttribute(name string) (string, error) {
	cid := cstr(e.id)
	cname := cstr(name)
	rc := int(C.aether_sel_embed_get_attribute(e.driver.h, cid, cname))
	C.free(unsafe.Pointer(cid))
	C.free(unsafe.Pointer(cname))
	v, err := e.driver.atomResult(rc)
	if err != nil {
		return "", err
	}
	// The atom yields a JSON string or null; null (absent attribute) -> "".
	s, _ := v.(string)
	return s, nil
}

// GetDomAttribute returns the literal DOM attribute (W3C getDomAttribute), with
// no property fallback.
func (e *WebElement) GetDomAttribute(name string) (interface{}, error) {
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

// ---- WebDriver-BiDi ---------------------------------------------------------

// bidiEventNames holds the common WebDriver-BiDi event names (W3C spec). Pass
// them to BiDi.Subscribe and match them in BiDi.NextEvent.
type bidiEventNames struct {
	LogEntryAdded     string
	ContextCreated    string
	ContextDestroyed  string
	NavigationStarted string
	DomContentLoaded  string
	Load              string
	DownloadWillBegin string
	BeforeRequestSent string
	ResponseStarted   string
	ResponseCompleted string
	FetchError        string
	RealmCreated      string
	RealmDestroyed    string
	Message           string
}

// BidiEvent is the set of common WebDriver-BiDi event names.
var BidiEvent = bidiEventNames{
	LogEntryAdded:     "log.entryAdded",
	ContextCreated:    "browsingContext.contextCreated",
	ContextDestroyed:  "browsingContext.contextDestroyed",
	NavigationStarted: "browsingContext.navigationStarted",
	DomContentLoaded:  "browsingContext.domContentLoaded",
	Load:              "browsingContext.load",
	DownloadWillBegin: "browsingContext.downloadWillBegin",
	BeforeRequestSent: "network.beforeRequestSent",
	ResponseStarted:   "network.responseStarted",
	ResponseCompleted: "network.responseCompleted",
	FetchError:        "network.fetchError",
	RealmCreated:      "script.realmCreated",
	RealmDestroyed:    "script.realmDestroyed",
	Message:           "script.message",
}

// BiDi is the event-driven BiDi channel for a session (over the demux C ABI).
//
// Commands and events multiplex over one WebSocket via the engine's shape-C
// demux (a single reader routes replies to an id table and events to a bounded
// queue), so replies stay correlated while events stream. Command ids are
// supplied automatically by a monotonic counter starting at 1.
type BiDi struct {
	h      unsafe.Pointer
	nextID int
}

func (b *BiDi) id() C.int {
	i := b.nextID
	b.nextID++
	return C.int(i)
}

// Subscribe issues session.subscribe for one or more event names and waits for
// the ack, returning the ack payload. After this, matching events arrive on the
// queue (drain via NextEvent).
func (b *BiDi) Subscribe(events ...string) (map[string]interface{}, error) {
	csv := cstr(strings.Join(events, ","))
	defer C.free(unsafe.Pointer(csv))
	return decodeBidiAck(takeString(C.aether_sel_embed_bidi_subscribe(b.h, b.id(), csv, C.int(10000))))
}

// Unsubscribe issues session.unsubscribe for one or more event names and waits
// for the ack, returning the ack payload.
func (b *BiDi) Unsubscribe(events ...string) (map[string]interface{}, error) {
	csv := cstr(strings.Join(events, ","))
	defer C.free(unsafe.Pointer(csv))
	return decodeBidiAck(takeString(C.aether_sel_embed_bidi_unsubscribe(b.h, b.id(), csv, C.int(10000))))
}

func decodeBidiAck(raw string) (map[string]interface{}, error) {
	if raw == "" {
		return map[string]interface{}{}, nil
	}
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return nil, fmt.Errorf("unmarshal bidi ack: %w", err)
	}
	return m, nil
}

// NextEvent blocks until an event whose method matches arrives, or timeoutMs
// elapses. It returns the event map, or nil on timeout/close. (Subscribe first.)
func (b *BiDi) NextEvent(method string, timeoutMs int) (map[string]interface{}, error) {
	cMethod := cstr(method)
	defer C.free(unsafe.Pointer(cMethod))
	raw := takeString(C.aether_sel_embed_bidi_wait_event(b.h, cMethod, C.int(timeoutMs)))
	if raw == "" {
		return nil, nil
	}
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return nil, fmt.Errorf("unmarshal bidi event: %w", err)
	}
	return m, nil
}

// Command issues any BiDi command and returns its reply payload. It lets a
// caller reach BiDi methods with no dedicated wrapper (script.evaluate,
// browsingContext.captureScreenshot, network.*, …). The command id is supplied
// automatically; the call sends then pump-polls until this id's reply arrives.
func (b *BiDi) Command(method string, params map[string]interface{}, timeoutMs int) (map[string]interface{}, error) {
	if params == nil {
		params = map[string]interface{}{}
	}
	pj, err := json.Marshal(params)
	if err != nil {
		return nil, fmt.Errorf("marshal bidi params: %w", err)
	}
	cMethod := cstr(method)
	cParams := cstr(string(pj))
	defer C.free(unsafe.Pointer(cMethod))
	defer C.free(unsafe.Pointer(cParams))
	cid := b.id()
	if int(C.aether_sel_embed_bidi_send(b.h, cid, cMethod, cParams)) != 0 {
		return nil, &Error{Code: -1, Message: "BiDi send failed: " + method}
	}
	const step = 50
	for waited := 0; waited < timeoutMs; waited += step {
		reply := takeString(C.aether_sel_embed_bidi_poll_reply(b.h, cid))
		if reply != "" {
			var m map[string]interface{}
			if err := json.Unmarshal([]byte(reply), &m); err != nil {
				return nil, fmt.Errorf("unmarshal bidi reply: %w", err)
			}
			return m, nil
		}
		if int(C.aether_sel_embed_bidi_pump(b.h, C.int(step))) < 0 {
			break
		}
	}
	return nil, &Error{Code: codeTimeout, Message: "BiDi command timed out: " + method}
}

// ---- typed convenience commands ----

// bidiConvenienceTimeout is the default timeout for the typed BiDi convenience
// commands when the caller passes none (matches the Python surface's defaults).
const bidiConvenienceTimeout = 30000

// decodeBidiReply unmarshals a convenience-command reply JSON into a map (the
// same reply shape as Command). An empty reply yields an empty map.
func decodeBidiReply(raw string) (map[string]interface{}, error) {
	if raw == "" {
		return map[string]interface{}{}, nil
	}
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return nil, fmt.Errorf("unmarshal bidi reply: %w", err)
	}
	return m, nil
}

// firstTimeout returns the single optional timeout, or bidiConvenienceTimeout.
func firstTimeout(timeoutMs []int) int {
	if len(timeoutMs) > 0 {
		return timeoutMs[0]
	}
	return bidiConvenienceTimeout
}

// GetTree issues browsingContext.getTree and returns the reply. Its
// ["result"]["contexts"] lists the browsing contexts (each with a "context" id).
func (b *BiDi) GetTree(timeoutMs ...int) (map[string]interface{}, error) {
	return decodeBidiReply(takeString(C.aether_sel_embed_bidi_get_tree(b.h, b.id(), C.int(firstTimeout(timeoutMs)))))
}

// TopContext returns the top-level browsing context id (the anchor for
// Evaluate/Navigate), or "" if the tree has none.
func (b *BiDi) TopContext(timeoutMs ...int) (string, error) {
	tree, err := b.GetTree(timeoutMs...)
	if err != nil {
		return "", err
	}
	result, _ := tree["result"].(map[string]interface{})
	contexts, _ := result["contexts"].([]interface{})
	if len(contexts) == 0 {
		return "", nil
	}
	c, _ := contexts[0].(map[string]interface{})
	id, _ := c["context"].(string)
	return id, nil
}

// Evaluate runs script.evaluate for an expression in the top context's realm,
// awaiting a returned promise, and returns the reply. Its ["result"]["result"]
// is the BiDi-typed value (e.g. {"type":"number","value":42}). This is BiDi's
// richer alternative to ExecuteScript — real realms, promise-awaiting, and
// structured value types.
func (b *BiDi) Evaluate(expr string, timeoutMs ...int) (map[string]interface{}, error) {
	t := firstTimeout(timeoutMs)
	ctx, err := b.TopContext(t)
	if err != nil {
		return nil, err
	}
	if ctx == "" {
		return nil, &Error{Code: 0, Message: "no browsing context for script.evaluate"}
	}
	cExpr := cstr(expr)
	cCtx := cstr(ctx)
	defer C.free(unsafe.Pointer(cExpr))
	defer C.free(unsafe.Pointer(cCtx))
	return decodeBidiReply(takeString(C.aether_sel_embed_bidi_script_evaluate(b.h, b.id(), cExpr, cCtx, C.int(t))))
}

// EvaluateValue runs script.evaluate and returns just the unwrapped value (the
// .value of the BiDi-typed result), or nil if it was not a simple value. Note:
// JSON numbers unmarshal to float64 in Go.
func (b *BiDi) EvaluateValue(expr string, timeoutMs ...int) (interface{}, error) {
	reply, err := b.Evaluate(expr, timeoutMs...)
	if err != nil {
		return nil, err
	}
	result, _ := reply["result"].(map[string]interface{})
	inner, _ := result["result"].(map[string]interface{})
	return inner["value"], nil
}

// Navigate issues browsingContext.navigate to url in the top context (waiting
// for the navigation to complete) and returns the reply.
func (b *BiDi) Navigate(url string, timeoutMs ...int) (map[string]interface{}, error) {
	t := firstTimeout(timeoutMs)
	ctx, err := b.TopContext(t)
	if err != nil {
		return nil, err
	}
	if ctx == "" {
		return nil, &Error{Code: 0, Message: "no browsing context for navigate"}
	}
	cCtx := cstr(ctx)
	cURL := cstr(url)
	defer C.free(unsafe.Pointer(cCtx))
	defer C.free(unsafe.Pointer(cURL))
	return decodeBidiReply(takeString(C.aether_sel_embed_bidi_navigate(b.h, b.id(), cCtx, cURL, C.int(t))))
}

// ---- network interception (observe / release / block requests) ----

// AddIntercept issues network.addIntercept for a URL pattern (a full parseable
// URL as a "string" pattern; empty intercepts all) at the given comma-separated
// phases (e.g. "beforeRequestSent"). Subscribe to the matching network.* event
// first if you want the paused-request events. Returns the intercept id from
// reply["result"]["intercept"].
func (b *BiDi) AddIntercept(phasesCsv, urlPattern string, timeoutMs ...int) (string, error) {
	cPhases := cstr(phasesCsv)
	cPattern := cstr(urlPattern)
	defer C.free(unsafe.Pointer(cPhases))
	defer C.free(unsafe.Pointer(cPattern))
	reply, err := decodeBidiReply(takeString(C.aether_sel_embed_bidi_network_add_intercept(b.h, b.id(), cPhases, cPattern, C.int(firstTimeout(timeoutMs)))))
	if err != nil {
		return "", err
	}
	result, _ := reply["result"].(map[string]interface{})
	id, _ := result["intercept"].(string)
	return id, nil
}

// RemoveIntercept issues network.removeIntercept for a previously added
// intercept id.
func (b *BiDi) RemoveIntercept(interceptID string, timeoutMs ...int) error {
	cID := cstr(interceptID)
	defer C.free(unsafe.Pointer(cID))
	_, err := decodeBidiReply(takeString(C.aether_sel_embed_bidi_network_remove_intercept(b.h, b.id(), cID, C.int(firstTimeout(timeoutMs)))))
	return err
}

// ContinueRequest lets a paused (intercepted) request proceed unchanged and
// returns the reply. requestID comes from a network event's
// params.request.request (see EventRequestID).
func (b *BiDi) ContinueRequest(requestID string, timeoutMs ...int) (map[string]interface{}, error) {
	cID := cstr(requestID)
	defer C.free(unsafe.Pointer(cID))
	return decodeBidiReply(takeString(C.aether_sel_embed_bidi_network_continue_request(b.h, b.id(), cID, C.int(firstTimeout(timeoutMs)))))
}

// FailRequest blocks a paused request (the ad/tracker-blocking case) and
// returns the reply. requestID comes from a network event's
// params.request.request (see EventRequestID).
func (b *BiDi) FailRequest(requestID string, timeoutMs ...int) (map[string]interface{}, error) {
	cID := cstr(requestID)
	defer C.free(unsafe.Pointer(cID))
	return decodeBidiReply(takeString(C.aether_sel_embed_bidi_network_fail_request(b.h, b.id(), cID, C.int(firstTimeout(timeoutMs)))))
}

// EventRequestID reads the network request id out of a network.beforeRequestSent
// (or other network) event: params.request.request. Returns "" if absent.
func EventRequestID(event map[string]interface{}) string {
	params, _ := event["params"].(map[string]interface{})
	request, _ := params["request"].(map[string]interface{})
	id, _ := request["request"].(string)
	return id
}

// LostEvents reports how many events the bounded queue has dropped since the
// last call (then resets) — so a consumer knows it missed events.
func (b *BiDi) LostEvents() int {
	return int(C.aether_sel_embed_bidi_lost_events(b.h))
}

// Close shuts the BiDi channel and releases its handle.
func (b *BiDi) Close() {
	if b.h != nil {
		C.aether_sel_embed_bidi_close(b.h)
		b.h = nil
	}
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
