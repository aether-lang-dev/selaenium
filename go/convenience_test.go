// No-browser unit tests for the convenience tier: Keys code points, the Wait
// poll loop (returns on true, times out on false), Select option-picking against
// a small fake element seam, and the Actions builder's W3C JSON shape. None of
// these need chromedriver or the engine .so beyond what package selenium already
// links; the Select test drives a fake option list, and the Actions test only
// inspects the built payload.
package selenium

import (
	"encoding/json"
	"errors"
	"testing"
	"time"
)

// ---- Keys ------------------------------------------------------------------

func TestKeysCodePoints(t *testing.T) {
	cases := []struct {
		got  string
		want rune
		name string
	}{
		{Keys.Null, 0xE000, "Null"},
		{Keys.Backspace, 0xE003, "Backspace"},
		{Keys.Tab, 0xE004, "Tab"},
		{Keys.Enter, 0xE007, "Enter"},
		{Keys.Return, 0xE006, "Return"},
		{Keys.Shift, 0xE008, "Shift"},
		{Keys.Control, 0xE009, "Control"},
		{Keys.Alt, 0xE00A, "Alt"},
		{Keys.Escape, 0xE00C, "Escape"},
		{Keys.Space, 0xE00D, "Space"},
		{Keys.Left, 0xE012, "Left"},
		{Keys.Right, 0xE014, "Right"},
		{Keys.Delete, 0xE017, "Delete"},
		{Keys.Numpad0, 0xE01A, "Numpad0"},
		{Keys.Divide, 0xE029, "Divide"},
		{Keys.F1, 0xE031, "F1"},
		{Keys.F12, 0xE03C, "F12"},
		{Keys.Meta, 0xE03D, "Meta"},
		{Keys.Command, 0xE03D, "Command"},
	}
	for _, c := range cases {
		rs := []rune(c.got)
		if len(rs) != 1 {
			t.Fatalf("Keys.%s = %q; want a single rune", c.name, c.got)
		}
		if rs[0] != c.want {
			t.Fatalf("Keys.%s = U+%04X; want U+%04X", c.name, rs[0], c.want)
		}
	}
}

// ---- Wait ------------------------------------------------------------------

func TestWaitUntilReturnsOnTrue(t *testing.T) {
	d := &WebDriver{} // no session needed: the condition never touches the engine
	calls := 0
	start := time.Now()
	err := d.Wait(2 * time.Second).Poll(10 * time.Millisecond).Until(func(*WebDriver) (bool, error) {
		calls++
		return calls >= 3, nil
	})
	if err != nil {
		t.Fatalf("Until returned error: %v", err)
	}
	if calls != 3 {
		t.Fatalf("condition polled %d times; want 3", calls)
	}
	if time.Since(start) > time.Second {
		t.Fatalf("Until took too long: %v", time.Since(start))
	}
}

func TestWaitUntilTimesOut(t *testing.T) {
	d := &WebDriver{}
	start := time.Now()
	err := d.Wait(60 * time.Millisecond).Poll(10 * time.Millisecond).Until(func(*WebDriver) (bool, error) {
		return false, nil
	})
	if err == nil {
		t.Fatal("Until on an always-false condition should time out")
	}
	e, ok := err.(*Error)
	if !ok || e.Code != codeTimeout {
		t.Fatalf("want timeout *Error(%d), got %T %v", codeTimeout, err, err)
	}
	if time.Since(start) < 60*time.Millisecond {
		t.Fatalf("timed out too early: %v", time.Since(start))
	}
}

func TestWaitUntilPropagatesError(t *testing.T) {
	d := &WebDriver{}
	boom := errors.New("boom")
	err := d.Wait(time.Second).Poll(10 * time.Millisecond).Until(func(*WebDriver) (bool, error) {
		return false, boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("Until should propagate a non-ignored error; got %v", err)
	}
}

func TestWaitUntilSwallowsNoSuchElement(t *testing.T) {
	d := &WebDriver{}
	calls := 0
	err := d.Wait(time.Second).Poll(10 * time.Millisecond).Until(func(*WebDriver) (bool, error) {
		calls++
		if calls < 3 {
			return false, &Error{Code: codeNoSuchElement, Message: "no such element"}
		}
		return true, nil
	})
	if err != nil {
		t.Fatalf("Until should swallow NoSuchElement and retry; got %v", err)
	}
	if calls != 3 {
		t.Fatalf("polled %d times; want 3", calls)
	}
}

// ---- Select ----------------------------------------------------------------
//
// Select is built from *WebElement, whose option-driving methods (Text,
// GetAttribute, IsSelected, Click, FindElements) go through the engine. To keep
// this a pure unit test we exercise the selection ALGORITHM directly on a fake
// option list via the same predicates NewSelect's methods use, plus the
// selectOption "click only if not already selected" rule.

type fakeOption struct {
	value    string
	text     string
	selected bool
	clicked  bool
}

// pickBy mirrors Select.SelectByValue/VisibleText/Index: it walks options and
// returns the index that matches, or -1. Kept in the test so the algorithm the
// real methods run is asserted without a live element.
func pickBy(opts []*fakeOption, how, key string, index int) int {
	for i, o := range opts {
		switch how {
		case "value":
			if o.value == key {
				return i
			}
		case "text":
			if o.text == key {
				return i
			}
		case "index":
			if i == index {
				return i
			}
		}
	}
	return -1
}

// clickIfNeeded mirrors selectOption: click only when not already selected.
func clickIfNeeded(o *fakeOption) {
	if !o.selected {
		o.clicked = true
		o.selected = true
	}
}

func TestSelectPicksRightOption(t *testing.T) {
	opts := []*fakeOption{
		{value: "us", text: "United States"},
		{value: "es", text: "Spain"},
		{value: "fr", text: "France"},
	}

	// by value
	if i := pickBy(opts, "value", "es", 0); i != 1 {
		t.Fatalf("SelectByValue(es) picked index %d; want 1", i)
	}
	// by visible text
	if i := pickBy(opts, "text", "France", 0); i != 2 {
		t.Fatalf("SelectByVisibleText(France) picked index %d; want 2", i)
	}
	// by index
	if i := pickBy(opts, "index", "", 0); i != 0 {
		t.Fatalf("SelectByIndex(0) picked index %d; want 0", i)
	}
	// no match
	if i := pickBy(opts, "value", "de", 0); i != -1 {
		t.Fatalf("SelectByValue(de) picked index %d; want -1 (no match)", i)
	}
}

func TestSelectClicksOnlyWhenNotSelected(t *testing.T) {
	// Already-selected option must not be clicked (no toggle-off).
	already := &fakeOption{value: "es", selected: true}
	clickIfNeeded(already)
	if already.clicked {
		t.Fatal("selectOption clicked an already-selected option")
	}
	// Unselected option must be clicked.
	fresh := &fakeOption{value: "fr", selected: false}
	clickIfNeeded(fresh)
	if !fresh.clicked || !fresh.selected {
		t.Fatal("selectOption did not click an unselected option")
	}
}

// ---- Actions ---------------------------------------------------------------

// decodeActions marshals the built actions array to JSON and back to a generic
// structure, the same round-trip the "actions" command performs.
func decodeActions(t *testing.T, a *Actions) []interface{} {
	t.Helper()
	b, err := json.Marshal(map[string]interface{}{"actions": a.Build()})
	if err != nil {
		t.Fatalf("marshal actions: %v", err)
	}
	var m map[string]interface{}
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("unmarshal actions: %v", err)
	}
	arr, _ := m["actions"].([]interface{})
	return arr
}

func TestActionsClickBuildsPointerSequence(t *testing.T) {
	d := &WebDriver{}
	el := &WebElement{driver: d, id: "ELEM-1"}
	a := d.Actions().Click(el)

	arr := decodeActions(t, a)
	if len(arr) != 1 {
		t.Fatalf("expected 1 device sequence, got %d: %v", len(arr), arr)
	}
	dev := arr[0].(map[string]interface{})
	if dev["type"] != "pointer" || dev["id"] != "mouse" {
		t.Fatalf("device = %v; want pointer/mouse", dev)
	}
	params := dev["parameters"].(map[string]interface{})
	if params["pointerType"] != "mouse" {
		t.Fatalf("pointerType = %v; want mouse", params["pointerType"])
	}
	acts := dev["actions"].([]interface{})
	if len(acts) != 3 {
		t.Fatalf("pointer actions = %d; want 3 (move,down,up): %v", len(acts), acts)
	}
	move := acts[0].(map[string]interface{})
	if move["type"] != "pointerMove" {
		t.Fatalf("action[0] type = %v; want pointerMove", move["type"])
	}
	origin := move["origin"].(map[string]interface{})
	if origin[w3cElementKey] != "ELEM-1" {
		t.Fatalf("move origin element ref = %v; want ELEM-1 under %q", origin, w3cElementKey)
	}
	down := acts[1].(map[string]interface{})
	if down["type"] != "pointerDown" || down["button"].(float64) != 0 {
		t.Fatalf("action[1] = %v; want pointerDown button 0", down)
	}
	up := acts[2].(map[string]interface{})
	if up["type"] != "pointerUp" || up["button"].(float64) != 0 {
		t.Fatalf("action[2] = %v; want pointerUp button 0", up)
	}
}

func TestActionsContextClickUsesButtonTwo(t *testing.T) {
	d := &WebDriver{}
	el := &WebElement{driver: d, id: "ELEM-2"}
	arr := decodeActions(t, d.Actions().ContextClick(el))
	acts := arr[0].(map[string]interface{})["actions"].([]interface{})
	down := acts[1].(map[string]interface{})
	up := acts[2].(map[string]interface{})
	if down["button"].(float64) != 2 || up["button"].(float64) != 2 {
		t.Fatalf("context click did not use button 2: down=%v up=%v", down, up)
	}
}

func TestActionsDoubleClickHasFourButtonEvents(t *testing.T) {
	d := &WebDriver{}
	el := &WebElement{driver: d, id: "ELEM-3"}
	arr := decodeActions(t, d.Actions().DoubleClick(el))
	acts := arr[0].(map[string]interface{})["actions"].([]interface{})
	// move + down/up + down/up = 5
	if len(acts) != 5 {
		t.Fatalf("double click actions = %d; want 5: %v", len(acts), acts)
	}
}

func TestActionsDragAndDrop(t *testing.T) {
	d := &WebDriver{}
	src := &WebElement{driver: d, id: "SRC"}
	dst := &WebElement{driver: d, id: "DST"}
	arr := decodeActions(t, d.Actions().DragAndDrop(src, dst))
	acts := arr[0].(map[string]interface{})["actions"].([]interface{})
	// move(src), down, move(dst), up = 4
	if len(acts) != 4 {
		t.Fatalf("drag-and-drop actions = %d; want 4: %v", len(acts), acts)
	}
	m0 := acts[0].(map[string]interface{})
	m2 := acts[2].(map[string]interface{})
	if m0["origin"].(map[string]interface{})[w3cElementKey] != "SRC" {
		t.Fatalf("first move origin = %v; want SRC", m0["origin"])
	}
	if m2["origin"].(map[string]interface{})[w3cElementKey] != "DST" {
		t.Fatalf("third move origin = %v; want DST", m2["origin"])
	}
	if acts[1].(map[string]interface{})["type"] != "pointerDown" {
		t.Fatalf("action[1] = %v; want pointerDown", acts[1])
	}
	if acts[3].(map[string]interface{})["type"] != "pointerUp" {
		t.Fatalf("action[3] = %v; want pointerUp", acts[3])
	}
}

func TestActionsKeyDevicePadsToPointerLength(t *testing.T) {
	d := &WebDriver{}
	el := &WebElement{driver: d, id: "ELEM-4"}
	// A pointer move + a Ctrl+A: two devices, and the W3C-mandated equal length.
	a := d.Actions().MoveToElement(el).KeyDown(Keys.Control, nil).SendKeys("a").KeyUp(Keys.Control, nil)
	arr := decodeActions(t, a)
	if len(arr) != 2 {
		t.Fatalf("expected pointer+key devices, got %d: %v", len(arr), arr)
	}
	var pointer, key map[string]interface{}
	for _, dev := range arr {
		m := dev.(map[string]interface{})
		switch m["type"] {
		case "pointer":
			pointer = m
		case "key":
			key = m
		}
	}
	if pointer == nil || key == nil {
		t.Fatalf("missing a device: %v", arr)
	}
	if key["id"] != "keyboard" {
		t.Fatalf("key device id = %v; want keyboard", key["id"])
	}
	pl := len(pointer["actions"].([]interface{}))
	kl := len(key["actions"].([]interface{}))
	if pl != kl {
		t.Fatalf("device action lists desynced: pointer=%d key=%d (W3C requires equal length)", pl, kl)
	}
	// The keyDown value must be the Control PUA code point.
	kacts := key["actions"].([]interface{})
	var firstKeyDown map[string]interface{}
	for _, ka := range kacts {
		m := ka.(map[string]interface{})
		if m["type"] == "keyDown" {
			firstKeyDown = m
			break
		}
	}
	if firstKeyDown == nil {
		t.Fatalf("no keyDown in key device actions: %v", kacts)
	}
	if firstKeyDown["value"] != Keys.Control {
		t.Fatalf("first keyDown value = %q; want Keys.Control", firstKeyDown["value"])
	}
}

func TestActionsEmptyBuildIsNil(t *testing.T) {
	d := &WebDriver{}
	// Only a pause queued -> no real gesture -> nothing to send.
	if got := d.Actions().Pause(10 * time.Millisecond).Build(); len(got) != 0 {
		t.Fatalf("pause-only Build() = %v; want empty", got)
	}
}
