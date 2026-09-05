// Package selenium's convenience tier: the everyday high-level helpers layered
// over the flat command seam (WebDriver.execute / WebElement.exec) — explicit
// Waits, a <select> dropdown helper, a fluent Actions builder, and the Keys
// constants. None of these add protocol logic: they compose the same commands
// the rest of the binding issues (findElement, getTitle, clickElement, the raw
// "actions" route), mirroring the reference native binding aether/webdriver.ae
// and the Python support/ helpers, rendered in idiomatic Go.
package selenium

import (
	"fmt"
	"strings"
	"time"
)

// ---- Keys (W3C special keys) ----------------------------------------------

// keySet is the type of the package-level Keys value. Its fields are the W3C
// WebDriver Unicode private-use code points for non-text keys (spec §17.4.2),
// the same code points every mainstream Selenium binding ships. Send them
// through WebElement.SendKeys or Actions.SendKeys / KeyDown / KeyUp; the engine
// forwards them unchanged.
type keySet struct {
	Null      string
	Cancel    string
	Help      string
	Backspace string
	Tab       string
	Clear     string
	Return    string
	Enter     string
	Shift     string
	Control   string
	Alt       string
	Pause     string
	Escape    string
	Space     string
	PageUp    string
	PageDown  string
	End       string
	Home      string
	Left      string
	Up        string
	Right     string
	Down      string
	Insert    string
	Delete    string
	Semicolon string
	Equals    string

	Numpad0   string
	Numpad1   string
	Numpad2   string
	Numpad3   string
	Numpad4   string
	Numpad5   string
	Numpad6   string
	Numpad7   string
	Numpad8   string
	Numpad9   string
	Multiply  string
	Add       string
	Separator string
	Subtract  string
	Decimal   string
	Divide    string

	F1  string
	F2  string
	F3  string
	F4  string
	F5  string
	F6  string
	F7  string
	F8  string
	F9  string
	F10 string
	F11 string
	F12 string

	Meta    string
	Command string
}

// Keys holds the mainstream Selenium special-key constants:
//
//	box.SendKeys("hello" + selenium.Keys.Enter)
//	drv.Actions().KeyDown(selenium.Keys.Control).SendKeys("a").KeyUp(selenium.Keys.Control).Perform()
var Keys = keySet{
	Null:      "\uE000",
	Cancel:    "\uE001",
	Help:      "\uE002",
	Backspace: "\uE003",
	Tab:       "\uE004",
	Clear:     "\uE005",
	Return:    "\uE006",
	Enter:     "\uE007",
	Shift:     "\uE008",
	Control:   "\uE009",
	Alt:       "\uE00A",
	Pause:     "\uE00B",
	Escape:    "\uE00C",
	Space:     "\uE00D",
	PageUp:    "\uE00E",
	PageDown:  "\uE00F",
	End:       "\uE010",
	Home:      "\uE011",
	Left:      "\uE012",
	Up:        "\uE013",
	Right:     "\uE014",
	Down:      "\uE015",
	Insert:    "\uE016",
	Delete:    "\uE017",
	Semicolon: "\uE018",
	Equals:    "\uE019",

	Numpad0:   "\uE01A",
	Numpad1:   "\uE01B",
	Numpad2:   "\uE01C",
	Numpad3:   "\uE01D",
	Numpad4:   "\uE01E",
	Numpad5:   "\uE01F",
	Numpad6:   "\uE020",
	Numpad7:   "\uE021",
	Numpad8:   "\uE022",
	Numpad9:   "\uE023",
	Multiply:  "\uE024",
	Add:       "\uE025",
	Separator: "\uE026",
	Subtract:  "\uE027",
	Decimal:   "\uE028",
	Divide:    "\uE029",

	F1:  "\uE031",
	F2:  "\uE032",
	F3:  "\uE033",
	F4:  "\uE034",
	F5:  "\uE035",
	F6:  "\uE036",
	F7:  "\uE037",
	F8:  "\uE038",
	F9:  "\uE039",
	F10: "\uE03A",
	F11: "\uE03B",
	F12: "\uE03C",

	Meta:    "\uE03D",
	Command: "\uE03D",
}

// Chord builds a modifier chord: modifier held while text is typed, then the
// sequence closed by the terminating NULL the protocol uses to release held
// modifiers \u2014 e.g. selenium.Keys.Chord(selenium.Keys.Control, "a") for
// select-all. This is the classic Keys.chord helper, rendered as a single
// string you pass to WebElement.SendKeys.
func (keySet) Chord(modifier, text string) string {
	return modifier + text + "\uE000"
}

// ---- Waits (explicit WebDriverWait + ExpectedConditions) -------------------

// DefaultPollInterval is the delay between condition polls for a Waiter, the
// mainstream 500ms default. The engine holds no thread, so the poll loop lives
// here in Go — exactly as the reference aether/webdriver.ae waits do.
const DefaultPollInterval = 500 * time.Millisecond

// Condition is a wait predicate: it is re-evaluated against the live driver on
// each poll and returns (true, nil) once satisfied. A returned error aborts the
// wait immediately (it is not swallowed); use a false return for "not yet".
// NoSuchElement errors are swallowed by Until so a not-yet-present element
// retries rather than aborting — matching mainstream's ignored_exceptions.
type Condition func(*WebDriver) (bool, error)

// Waiter polls a Condition until it holds or the timeout elapses. Build one with
// WebDriver.Wait and drive it with Until:
//
//	err := drv.Wait(10 * time.Second).Until(func(d *selenium.WebDriver) (bool, error) {
//		t, err := d.Title()
//		return strings.Contains(t, "Loaded"), err
//	})
type Waiter struct {
	driver  *WebDriver
	timeout time.Duration
	poll    time.Duration
}

// Wait returns a Waiter that polls at DefaultPollInterval until timeout. Mirrors
// mainstream WebDriverWait(driver, timeout) — but with a Go time.Duration.
func (d *WebDriver) Wait(timeout time.Duration) *Waiter {
	return &Waiter{driver: d, timeout: timeout, poll: DefaultPollInterval}
}

// Poll overrides the poll interval (fluent). A non-positive value is ignored.
func (w *Waiter) Poll(interval time.Duration) *Waiter {
	if interval > 0 {
		w.poll = interval
	}
	return w
}

// Until polls cond until it returns true, then returns nil. A non-nil error from
// cond (other than a swallowed NoSuchElement) aborts immediately. If the
// deadline passes first, it returns a timeout *Error. The condition re-reads the
// live DOM each attempt — the point of an explicit wait over a fixed sleep.
func (w *Waiter) Until(cond Condition) error {
	deadline := time.Now().Add(w.timeout)
	var lastErr error
	for {
		ok, err := cond(w.driver)
		switch {
		case err != nil && IsNoSuchElement(err):
			lastErr = err
		case err != nil:
			return err
		case ok:
			return nil
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(w.poll)
	}
	msg := fmt.Sprintf("timed out after %s waiting for condition", w.timeout)
	if lastErr != nil {
		msg = fmt.Sprintf("%s (last error: %v)", msg, lastErr)
	}
	return &Error{Code: codeTimeout, Message: msg}
}

// UntilNot polls cond until it returns false (or a swallowed NoSuchElement),
// then returns nil — the inverse of Until (mainstream until_not). It returns a
// timeout *Error if cond stays true past the deadline.
func (w *Waiter) UntilNot(cond Condition) error {
	return w.Until(func(d *WebDriver) (bool, error) {
		ok, err := cond(d)
		if err != nil && IsNoSuchElement(err) {
			return true, nil
		}
		if err != nil {
			return false, err
		}
		return !ok, nil
	})
}

// ---- ExpectedConditions as convenience waits (mirror aether/webdriver.ae) ---

// WaitForElement waits until an element matching sel is present in the DOM and
// returns it (classic elementLocated). Times out with a *Error.
func (d *WebDriver) WaitForElement(sel Selector, timeout time.Duration) (*WebElement, error) {
	var found *WebElement
	err := d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		el, err := dr.FindElement(sel)
		if err != nil {
			if IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		found = el
		return true, nil
	})
	if err != nil {
		return nil, err
	}
	return found, nil
}

// WaitForVisible waits until an element matching sel is present AND displayed,
// returning it (classic elementIsVisible folded with elementLocated).
func (d *WebDriver) WaitForVisible(sel Selector, timeout time.Duration) (*WebElement, error) {
	var found *WebElement
	err := d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		el, err := dr.FindElement(sel)
		if err != nil {
			if IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		shown, err := el.IsDisplayed()
		if err != nil {
			// A stale/removed element between find and check is a retry, not a fail.
			if IsStaleElement(err) || IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		if shown {
			found = el
			return true, nil
		}
		return false, nil
	})
	if err != nil {
		return nil, err
	}
	return found, nil
}

// WaitForClickable waits until an element matching sel is present, displayed AND
// enabled (clickable), returning it.
func (d *WebDriver) WaitForClickable(sel Selector, timeout time.Duration) (*WebElement, error) {
	var found *WebElement
	err := d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		el, err := dr.FindElement(sel)
		if err != nil {
			if IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		shown, err := el.IsDisplayed()
		if err != nil {
			if IsStaleElement(err) || IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		if !shown {
			return false, nil
		}
		enabled, err := el.IsEnabled()
		if err != nil {
			if IsStaleElement(err) || IsNoSuchElement(err) {
				return false, nil
			}
			return false, err
		}
		if enabled {
			found = el
			return true, nil
		}
		return false, nil
	})
	if err != nil {
		return nil, err
	}
	return found, nil
}

// WaitUntilGone waits until NO element matches sel — it is absent or removed
// (classic stalenessOf by locator). Returns nil once gone, or a timeout *Error.
func (d *WebDriver) WaitUntilGone(sel Selector, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		_, err := dr.FindElement(sel)
		if err != nil {
			if IsNoSuchElement(err) {
				return true, nil
			}
			return false, err
		}
		return false, nil
	})
}

// WaitForTitleIs waits until the page title equals want.
func (d *WebDriver) WaitForTitleIs(want string, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		t, err := dr.Title()
		return t == want, err
	})
}

// WaitForTitleContains waits until the page title contains substr.
func (d *WebDriver) WaitForTitleContains(substr string, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		t, err := dr.Title()
		return strings.Contains(t, substr), err
	})
}

// WaitForURLIs waits until the current URL equals want.
func (d *WebDriver) WaitForURLIs(want string, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		u, err := dr.CurrentURL()
		return u == want, err
	})
}

// WaitForURLContains waits until the current URL contains substr.
func (d *WebDriver) WaitForURLContains(substr string, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		u, err := dr.CurrentURL()
		return strings.Contains(u, substr), err
	})
}

// WaitForTextContains waits until el's text contains substr (re-reading the live
// element each poll — the right tool when a click re-renders from a server push).
func (d *WebDriver) WaitForTextContains(el *WebElement, substr string, timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		txt, err := el.Text()
		return strings.Contains(txt, substr), err
	})
}

// WaitForAlert waits until a JavaScript alert is present (classic alertIsPresent).
func (d *WebDriver) WaitForAlert(timeout time.Duration) error {
	return d.Wait(timeout).Until(func(dr *WebDriver) (bool, error) {
		if _, err := dr.AlertText(); err != nil {
			return false, nil
		}
		return true, nil
	})
}

// ---- element-scoped finds (needed by Select; generally useful) -------------

// FindElement finds a descendant of this element matching sel (W3C
// findElementFromElement). Same locator normalization as WebDriver.FindElement.
func (e *WebElement) FindElement(sel Selector) (*WebElement, error) {
	v, err := e.exec("findChildElement", decodeBy(sel))
	if err != nil {
		return nil, err
	}
	id, err := elementID(v)
	if err != nil {
		return nil, err
	}
	return &WebElement{driver: e.driver, id: id}, nil
}

// FindElements finds all descendants of this element matching sel (W3C
// findElementsFromElement).
func (e *WebElement) FindElements(sel Selector) ([]*WebElement, error) {
	v, err := e.exec("findChildElements", decodeBy(sel))
	if err != nil {
		return nil, err
	}
	return elementList(e.driver, v)
}

// ---- Select (<select> dropdown helper) -------------------------------------

// Select wraps a <select> WebElement and drives it by finding and clicking its
// <option> children — the same approach mainstream Selenium's Select uses:
//
//	sel, err := selenium.NewSelect(el)
//	sel.SelectByVisibleText("Spain")
type Select struct {
	el         *WebElement
	IsMultiple bool
}

// NewSelect wraps a <select> element. It returns an error if el is not a
// <select> (matching mainstream's constructor guard).
func NewSelect(el *WebElement) (*Select, error) {
	if el == nil {
		return nil, &Error{Code: 1, Message: "NewSelect: nil element"}
	}
	tag, err := el.TagName()
	if err != nil {
		return nil, err
	}
	if strings.ToLower(tag) != "select" {
		return nil, &Error{Code: 1, Message: fmt.Sprintf("Select only works on <select> elements, not <%s>", tag)}
	}
	multi, _, _ := el.GetAttribute("multiple")
	return &Select{el: el, IsMultiple: multi != "" && multi != "false"}, nil
}

// Options returns the <option> children of the wrapped <select>.
func (s *Select) Options() ([]*WebElement, error) {
	return s.el.FindElements(By.TagName("option"))
}

// AllSelectedOptions returns every currently-selected <option>.
func (s *Select) AllSelectedOptions() ([]*WebElement, error) {
	opts, err := s.Options()
	if err != nil {
		return nil, err
	}
	var out []*WebElement
	for _, o := range opts {
		sel, err := o.IsSelected()
		if err != nil {
			return nil, err
		}
		if sel {
			out = append(out, o)
		}
	}
	return out, nil
}

// FirstSelectedOption returns the first selected <option>, or a NoSuchElement
// error if none is selected.
func (s *Select) FirstSelectedOption() (*WebElement, error) {
	opts, err := s.Options()
	if err != nil {
		return nil, err
	}
	for _, o := range opts {
		sel, err := o.IsSelected()
		if err != nil {
			return nil, err
		}
		if sel {
			return o, nil
		}
	}
	return nil, &Error{Code: codeNoSuchElement, Message: "no option is selected"}
}

// SelectByValue selects the <option> whose value attribute equals value.
func (s *Select) SelectByValue(value string) error {
	opts, err := s.Options()
	if err != nil {
		return err
	}
	for _, o := range opts {
		v, _, err := o.GetAttribute("value")
		if err != nil {
			return err
		}
		if v == value {
			return selectOption(o)
		}
	}
	return &Error{Code: codeNoSuchElement, Message: fmt.Sprintf("no option with value %q", value)}
}

// SelectByVisibleText selects the <option> whose displayed text equals text.
func (s *Select) SelectByVisibleText(text string) error {
	opts, err := s.Options()
	if err != nil {
		return err
	}
	for _, o := range opts {
		t, err := o.Text()
		if err != nil {
			return err
		}
		if t == text {
			return selectOption(o)
		}
	}
	return &Error{Code: codeNoSuchElement, Message: fmt.Sprintf("no option with visible text %q", text)}
}

// SelectByIndex selects the <option> at the zero-based index.
func (s *Select) SelectByIndex(index int) error {
	opts, err := s.Options()
	if err != nil {
		return err
	}
	if index < 0 || index >= len(opts) {
		return &Error{Code: codeNoSuchElement, Message: fmt.Sprintf("no option at index %d", index)}
	}
	return selectOption(opts[index])
}

// DeselectAll deselects every selected option (multi-select only). It returns
// an error on a single-select, mirroring mainstream's NotImplementedError.
func (s *Select) DeselectAll() error {
	if !s.IsMultiple {
		return &Error{Code: 1, Message: "DeselectAll only makes sense on a multi-select"}
	}
	opts, err := s.Options()
	if err != nil {
		return err
	}
	for _, o := range opts {
		sel, err := o.IsSelected()
		if err != nil {
			return err
		}
		if sel {
			if err := o.Click(); err != nil {
				return err
			}
		}
	}
	return nil
}

// selectOption clicks an option only if it is not already selected (so a click
// never toggles an already-chosen option off in a multi-select).
func selectOption(o *WebElement) error {
	sel, err := o.IsSelected()
	if err != nil {
		return err
	}
	if sel {
		return nil
	}
	return o.Click()
}

// ---- Actions (fluent W3C input builder) ------------------------------------

// The W3C actions builder appends to two virtual-device action lists (a pointer
// "mouse" and a key "keyboard"); Perform posts the whole sequence in one
// "actions" command. This is the same wire shape the reference
// aether/webdriver.ae action_* helpers and the Python ActionChains emit.

// Actions is a fluent input-gesture builder. Chain gestures then Perform:
//
//	drv.Actions().MoveToElement(menu).Click(item).Perform()
type Actions struct {
	driver  *WebDriver
	pointer []map[string]interface{}
	key     []map[string]interface{}
}

// Actions starts a new fluent gesture builder bound to this session.
func (d *WebDriver) Actions() *Actions {
	return &Actions{driver: d}
}

func elementOrigin(el *WebElement) map[string]interface{} {
	return map[string]interface{}{"origin": map[string]interface{}{w3cElementKey: el.id}}
}

// MoveToElement moves the pointer to the centre of el (hover).
func (a *Actions) MoveToElement(el *WebElement) *Actions {
	move := map[string]interface{}{"type": "pointerMove", "duration": 100, "x": 0, "y": 0}
	for k, v := range elementOrigin(el) {
		move[k] = v
	}
	a.pointer = append(a.pointer, move)
	return a.sync()
}

// Click clicks (left button) at the current pointer position; if el is non-nil,
// it moves there first. Pass nil to click where the pointer already is.
func (a *Actions) Click(el *WebElement) *Actions {
	if el != nil {
		a.MoveToElement(el)
	}
	a.pointer = append(a.pointer,
		map[string]interface{}{"type": "pointerDown", "button": 0},
		map[string]interface{}{"type": "pointerUp", "button": 0})
	return a.sync()
}

// ContextClick right-clicks (button 2) at el's centre (or the current position
// if el is nil).
func (a *Actions) ContextClick(el *WebElement) *Actions {
	if el != nil {
		a.MoveToElement(el)
	}
	a.pointer = append(a.pointer,
		map[string]interface{}{"type": "pointerDown", "button": 2},
		map[string]interface{}{"type": "pointerUp", "button": 2})
	return a.sync()
}

// DoubleClick double-clicks (left button) at el's centre (or the current
// position if el is nil).
func (a *Actions) DoubleClick(el *WebElement) *Actions {
	if el != nil {
		a.MoveToElement(el)
	}
	for i := 0; i < 2; i++ {
		a.pointer = append(a.pointer,
			map[string]interface{}{"type": "pointerDown", "button": 0},
			map[string]interface{}{"type": "pointerUp", "button": 0})
	}
	return a.sync()
}

// ClickAndHold presses the left button (without releasing) at el's centre (or
// the current position if el is nil) — the start of a drag.
func (a *Actions) ClickAndHold(el *WebElement) *Actions {
	if el != nil {
		a.MoveToElement(el)
	}
	a.pointer = append(a.pointer, map[string]interface{}{"type": "pointerDown", "button": 0})
	return a.sync()
}

// Release releases the left button at el's centre (or the current position if
// el is nil) — the end of a drag.
func (a *Actions) Release(el *WebElement) *Actions {
	if el != nil {
		a.MoveToElement(el)
	}
	a.pointer = append(a.pointer, map[string]interface{}{"type": "pointerUp", "button": 0})
	return a.sync()
}

// DragAndDrop presses at source, moves to target, and releases.
func (a *Actions) DragAndDrop(source, target *WebElement) *Actions {
	return a.ClickAndHold(source).MoveToElement(target).Release(nil)
}

// KeyDown presses key (holds it down). If el is non-nil, it clicks el first to
// focus it. Use a Keys.* modifier (Shift/Control/Alt/Meta) or a character.
func (a *Actions) KeyDown(key string, el *WebElement) *Actions {
	if el != nil {
		a.Click(el)
	}
	a.key = append(a.key, map[string]interface{}{"type": "keyDown", "value": key})
	return a.sync()
}

// KeyUp releases key.
func (a *Actions) KeyUp(key string, el *WebElement) *Actions {
	a.key = append(a.key, map[string]interface{}{"type": "keyUp", "value": key})
	return a.sync()
}

// SendKeys types each character of every argument (a keyDown+keyUp pair per
// rune) on the key device at the current focus.
func (a *Actions) SendKeys(chunks ...string) *Actions {
	for _, chunk := range chunks {
		for _, r := range chunk {
			ch := string(r)
			a.key = append(a.key,
				map[string]interface{}{"type": "keyDown", "value": ch},
				map[string]interface{}{"type": "keyUp", "value": ch})
		}
	}
	return a.sync()
}

// Pause inserts a pause of d on the pointer device (both devices stay in step).
func (a *Actions) Pause(d time.Duration) *Actions {
	a.pointer = append(a.pointer, map[string]interface{}{"type": "pause", "duration": int(d.Milliseconds())})
	return a.sync()
}

// Build returns the W3C actions array this builder has accumulated — the value
// of the top-level "actions" key. Exposed so a caller (or a test) can inspect
// the payload without sending it; Perform builds and posts the same array.
func (a *Actions) Build() []interface{} {
	var actions []interface{}
	if hasNonPause(a.pointer) {
		actions = append(actions, map[string]interface{}{
			"type":       "pointer",
			"id":         "mouse",
			"parameters": map[string]interface{}{"pointerType": "mouse"},
			"actions":    toIfaceSlice(a.pointer),
		})
	}
	if hasNonPause(a.key) {
		actions = append(actions, map[string]interface{}{
			"type":    "key",
			"id":      "keyboard",
			"actions": toIfaceSlice(a.key),
		})
	}
	return actions
}

// Perform posts the accumulated gesture sequence in one "actions" command. It is
// a no-op (nil) when nothing but pauses was queued.
func (a *Actions) Perform() error {
	actions := a.Build()
	if len(actions) == 0 {
		return nil
	}
	return a.driver.PerformActions(actions)
}

// sync keeps both device action lists the same length (W3C requires every
// device's list to be the same length), padding the shorter with zero pauses so
// gestures on one device don't desync ticks.
func (a *Actions) sync() *Actions {
	n := len(a.pointer)
	if len(a.key) > n {
		n = len(a.key)
	}
	for len(a.pointer) < n {
		a.pointer = append(a.pointer, map[string]interface{}{"type": "pause", "duration": 0})
	}
	for len(a.key) < n {
		a.key = append(a.key, map[string]interface{}{"type": "pause", "duration": 0})
	}
	return a
}

func hasNonPause(actions []map[string]interface{}) bool {
	for _, a := range actions {
		if a["type"] != "pause" {
			return true
		}
	}
	return false
}

func toIfaceSlice(actions []map[string]interface{}) []interface{} {
	out := make([]interface{}, len(actions))
	for i, a := range actions {
		out[i] = a
	}
	return out
}
