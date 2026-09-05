//! Fluent action builder — the `Actions` / `ActionChains` convenience tier over
//! the raw `actions` route. Queue gestures with chained calls, then
//! [`Actions::perform`]:
//!
//! ```no_run
//! # use selenium::WebDriver;
//! # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
//! # let menu = d.find_element(selenium::By::css("#menu")).unwrap();
//! # let item = d.find_element(selenium::By::css("#item")).unwrap();
//! d.actions().move_to_element(&menu).click(Some(&item)).perform().unwrap();
//! ```
//!
//! Each call appends to a W3C actions sequence (a pointer virtual device and a
//! key virtual device); [`perform`] posts the whole sequence in one `actions`
//! command. This is the same wire shape the reference `aether/webdriver.ae`
//! action_* helpers and the Python `ActionChains` emit. The builder borrows the
//! driver for its lifetime, so it can `perform()` against it.
//!
//! [`perform`]: Actions::perform

use crate::{json, Json, Result, WebDriver, WebElement, W3C_ELEMENT_KEY};

/// A queued sequence of W3C input actions, built fluently and posted in one
/// `actions` command by [`Actions::perform`]. Obtain one from
/// [`WebDriver::actions`].
#[derive(Debug)]
pub struct Actions<'a> {
    driver: &'a WebDriver,
    seq: Seq,
}

/// The driver-free accumulation core: the pointer and key device action lists,
/// plus the W3C-shape assembly in [`Seq::build`]. Split out from [`Actions`] so
/// the gesture-to-JSON logic is unit-testable with no browser (it needs no
/// driver — only element ids).
#[derive(Debug, Default, Clone)]
struct Seq {
    pointer: Vec<Json>,
    key: Vec<Json>,
}

fn pause(duration_ms: i64) -> Json {
    json::obj(vec![("type", json::s("pause")), ("duration", json::n(duration_ms as f64))])
}

fn move_to(id: &str) -> Json {
    let origin = json::obj(vec![(W3C_ELEMENT_KEY, json::s(id))]);
    json::obj(vec![
        ("type", json::s("pointerMove")),
        ("duration", json::n(100.0)),
        ("x", json::n(0.0)),
        ("y", json::n(0.0)),
        ("origin", origin),
    ])
}

fn button_down(button: i64) -> Json {
    json::obj(vec![("type", json::s("pointerDown")), ("button", json::n(button as f64))])
}
fn button_up(button: i64) -> Json {
    json::obj(vec![("type", json::s("pointerUp")), ("button", json::n(button as f64))])
}
fn key_event(kind: &str, value: char) -> Json {
    json::obj(vec![("type", json::s(kind)), ("value", json::s(&value.to_string()))])
}
fn is_pause(a: &Json) -> bool {
    a.get("type").and_then(|t| t.as_str()) == Some("pause")
}

impl Seq {
    fn move_to_element(&mut self, id: &str) {
        self.pointer.push(move_to(id));
        self.sync_lengths();
    }
    fn click(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.pointer.push(move_to(id));
        }
        self.pointer.push(button_down(0));
        self.pointer.push(button_up(0));
        self.sync_lengths();
    }
    fn context_click(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.pointer.push(move_to(id));
        }
        self.pointer.push(button_down(2));
        self.pointer.push(button_up(2));
        self.sync_lengths();
    }
    fn double_click(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.pointer.push(move_to(id));
        }
        for _ in 0..2 {
            self.pointer.push(button_down(0));
            self.pointer.push(button_up(0));
        }
        self.sync_lengths();
    }
    fn click_and_hold(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.pointer.push(move_to(id));
        }
        self.pointer.push(button_down(0));
        self.sync_lengths();
    }
    fn release(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.pointer.push(move_to(id));
        }
        self.pointer.push(button_up(0));
        self.sync_lengths();
    }
    fn key_down(&mut self, key: char) {
        self.key.push(key_event("keyDown", key));
        self.sync_lengths();
    }
    fn key_up(&mut self, key: char) {
        self.key.push(key_event("keyUp", key));
        self.sync_lengths();
    }
    fn send_keys(&mut self, text: &str) {
        for ch in text.chars() {
            self.key.push(key_event("keyDown", ch));
            self.key.push(key_event("keyUp", ch));
        }
        self.sync_lengths();
    }
    fn pause(&mut self, duration_ms: i64) {
        self.pointer.push(pause(duration_ms));
        self.sync_lengths();
    }

    /// The W3C `actions` array assembled from the two device lists. A device
    /// sub-array is emitted only when it holds a real (non-pause) action,
    /// matching the Python reference.
    fn build(&self) -> Vec<Json> {
        let mut actions = Vec::new();
        if self.pointer.iter().any(|a| !is_pause(a)) {
            actions.push(json::obj(vec![
                ("type", json::s("pointer")),
                ("id", json::s("mouse")),
                ("parameters", json::obj(vec![("pointerType", json::s("mouse"))])),
                ("actions", Json::Arr(self.pointer.clone())),
            ]));
        }
        if self.key.iter().any(|a| !is_pause(a)) {
            actions.push(json::obj(vec![
                ("type", json::s("key")),
                ("id", json::s("keyboard")),
                ("actions", Json::Arr(self.key.clone())),
            ]));
        }
        actions
    }

    /// W3C requires every device's action list to be the same length; pad the
    /// shorter device with zero-duration pauses so gestures on one device don't
    /// desync the other's ticks. Mirrors the Python reference's `_sync_lengths`.
    fn sync_lengths(&mut self) {
        let n = self.pointer.len().max(self.key.len());
        while self.pointer.len() < n {
            self.pointer.push(pause(0));
        }
        while self.key.len() < n {
            self.key.push(pause(0));
        }
    }
}

impl<'a> Actions<'a> {
    pub(crate) fn new(driver: &'a WebDriver) -> Actions<'a> {
        Actions { driver, seq: Seq::default() }
    }

    // ---- pointer gestures ----

    /// Move the pointer to the centre of `element` (the path for hover, and the
    /// anchor for a subsequent click/drag).
    pub fn move_to_element(mut self, element: &WebElement<'_>) -> Self {
        self.seq.move_to_element(element.id());
        self
    }

    /// Left-click. With `Some(element)`, moves to it first; with `None`, clicks
    /// wherever the pointer currently is.
    pub fn click(mut self, element: Option<&WebElement<'_>>) -> Self {
        self.seq.click(element.map(|e| e.id()));
        self
    }

    /// Right-click (contextmenu). Moves to `element` first when given.
    pub fn context_click(mut self, element: Option<&WebElement<'_>>) -> Self {
        self.seq.context_click(element.map(|e| e.id()));
        self
    }

    /// Double-click. Moves to `element` first when given.
    pub fn double_click(mut self, element: Option<&WebElement<'_>>) -> Self {
        self.seq.double_click(element.map(|e| e.id()));
        self
    }

    /// Press and hold the left button (the start of a drag). Moves to `element`
    /// first when given.
    pub fn click_and_hold(mut self, element: Option<&WebElement<'_>>) -> Self {
        self.seq.click_and_hold(element.map(|e| e.id()));
        self
    }

    /// Release the held left button. Moves to `element` first when given.
    pub fn release(mut self, element: Option<&WebElement<'_>>) -> Self {
        self.seq.release(element.map(|e| e.id()));
        self
    }

    /// Drag `source` onto `target` (press at source, move to target, release).
    pub fn drag_and_drop(mut self, source: &WebElement<'_>, target: &WebElement<'_>) -> Self {
        self.seq.click_and_hold(Some(source.id()));
        self.seq.move_to_element(target.id());
        self.seq.release(None);
        self
    }

    // ---- key gestures ----

    /// Press (and hold) a key on the keyboard device — pair with
    /// [`Actions::key_up`] for a chord.
    pub fn key_down(mut self, key: char) -> Self {
        self.seq.key_down(key);
        self
    }

    /// Release a previously pressed key.
    pub fn key_up(mut self, key: char) -> Self {
        self.seq.key_up(key);
        self
    }

    /// Type `text` (a keyDown+keyUp per character) on the keyboard device —
    /// accepts [`Keys`] constants embedded in the string.
    ///
    /// [`Keys`]: crate::Keys
    pub fn send_keys(mut self, text: &str) -> Self {
        self.seq.send_keys(text);
        self
    }

    /// Insert a pause (ms) on the pointer device — a deliberate delay tick.
    pub fn pause(mut self, duration_ms: i64) -> Self {
        self.seq.pause(duration_ms);
        self
    }

    // ---- terminal ----

    /// The W3C `actions` array this builder has accumulated (the value of the
    /// top-level `actions` key). [`perform`] posts exactly this; exposed so a
    /// caller (or a test) can inspect the wire shape without a browser.
    ///
    /// [`perform`]: Actions::perform
    pub fn build(&self) -> Vec<Json> {
        self.seq.build()
    }

    /// Post the queued gestures as one `actions` command. A no-op (no request)
    /// when nothing but pauses was queued.
    pub fn perform(self) -> Result<()> {
        let actions = self.seq.build();
        if actions.is_empty() {
            return Ok(());
        }
        self.driver.perform_actions(actions)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Pull the sole action of a single-device build, asserting device type/id.
    fn device<'a>(actions: &'a [Json], want_type: &str) -> &'a Json {
        actions
            .iter()
            .find(|d| d.get("type").and_then(|t| t.as_str()) == Some(want_type))
            .unwrap_or_else(|| panic!("no {want_type} device in {actions:?}"))
    }

    fn inner(device: &Json) -> &Vec<Json> {
        device.get("actions").and_then(|a| a.as_array()).unwrap()
    }

    #[test]
    fn click_builds_move_down_up_on_the_mouse_device() {
        let mut s = Seq::default();
        s.click(Some("E1"));
        let built = s.build();
        assert_eq!(built.len(), 1, "only the pointer device");
        let ptr = device(&built, "pointer");
        assert_eq!(ptr.get("id").and_then(|v| v.as_str()), Some("mouse"));
        assert_eq!(
            ptr.get("parameters").and_then(|p| p.get("pointerType")).and_then(|v| v.as_str()),
            Some("mouse")
        );
        let acts = inner(ptr);
        assert_eq!(acts.len(), 3);
        // pointerMove with the element origin key.
        assert_eq!(acts[0].get("type").and_then(|v| v.as_str()), Some("pointerMove"));
        assert_eq!(
            acts[0].get("origin").and_then(|o| o.get(W3C_ELEMENT_KEY)).and_then(|v| v.as_str()),
            Some("E1")
        );
        assert_eq!(acts[1].get("type").and_then(|v| v.as_str()), Some("pointerDown"));
        assert_eq!(acts[1].get("button").and_then(|v| v.as_f64()), Some(0.0));
        assert_eq!(acts[2].get("type").and_then(|v| v.as_str()), Some("pointerUp"));
    }

    #[test]
    fn context_click_uses_button_2() {
        let mut s = Seq::default();
        s.context_click(Some("E1"));
        let built = s.build();
        let acts = inner(device(&built, "pointer"));
        assert_eq!(acts[1].get("button").and_then(|v| v.as_f64()), Some(2.0));
        assert_eq!(acts[2].get("button").and_then(|v| v.as_f64()), Some(2.0));
    }

    #[test]
    fn double_click_emits_two_down_up_pairs() {
        let mut s = Seq::default();
        s.double_click(None);
        let acts = inner(device(&s.build(), "pointer")).clone();
        let downs = acts.iter().filter(|a| a.get("type").and_then(|v| v.as_str()) == Some("pointerDown")).count();
        let ups = acts.iter().filter(|a| a.get("type").and_then(|v| v.as_str()) == Some("pointerUp")).count();
        assert_eq!((downs, ups), (2, 2));
    }

    #[test]
    fn drag_and_drop_is_hold_move_release() {
        let mut s = Seq::default();
        s.click_and_hold(Some("SRC"));
        s.move_to_element("TGT");
        s.release(None);
        let built = s.build();
        let acts = inner(device(&built, "pointer"));
        assert_eq!(acts[0].get("type").and_then(|v| v.as_str()), Some("pointerMove"));
        assert_eq!(
            acts[0].get("origin").and_then(|o| o.get(W3C_ELEMENT_KEY)).and_then(|v| v.as_str()),
            Some("SRC")
        );
        assert_eq!(acts[1].get("type").and_then(|v| v.as_str()), Some("pointerDown"));
        assert_eq!(acts[2].get("type").and_then(|v| v.as_str()), Some("pointerMove"));
        assert_eq!(
            acts[2].get("origin").and_then(|o| o.get(W3C_ELEMENT_KEY)).and_then(|v| v.as_str()),
            Some("TGT")
        );
        assert_eq!(acts[3].get("type").and_then(|v| v.as_str()), Some("pointerUp"));
    }

    #[test]
    fn send_keys_builds_the_key_device_with_down_up_per_char() {
        let mut s = Seq::default();
        s.send_keys("hi");
        let built = s.build();
        assert_eq!(built.len(), 1, "only the key device");
        let kbd = device(&built, "key");
        assert_eq!(kbd.get("id").and_then(|v| v.as_str()), Some("keyboard"));
        let acts = inner(kbd);
        assert_eq!(acts.len(), 4);
        assert_eq!(acts[0].get("type").and_then(|v| v.as_str()), Some("keyDown"));
        assert_eq!(acts[0].get("value").and_then(|v| v.as_str()), Some("h"));
        assert_eq!(acts[1].get("type").and_then(|v| v.as_str()), Some("keyUp"));
        assert_eq!(acts[3].get("value").and_then(|v| v.as_str()), Some("i"));
    }

    #[test]
    fn special_key_down_up_carries_the_pua_code_point() {
        use crate::Keys;
        let mut s = Seq::default();
        s.key_down(Keys::CONTROL);
        s.key_up(Keys::CONTROL);
        let built = s.build();
        let acts = inner(device(&built, "key"));
        assert_eq!(acts[0].get("value").and_then(|v| v.as_str()), Some("\u{E009}"));
    }

    #[test]
    fn mixed_devices_are_length_synced_with_pauses() {
        // A pointer click (3 ticks) then one key press (would be 1) must pad the
        // key device up to length 3 so the ticks line up.
        let mut s = Seq::default();
        s.click(Some("E1")); // 3 pointer actions; key padded to 3
        s.send_keys("x"); // +2 key actions -> key 5; pointer padded to 5
        assert_eq!(s.pointer.len(), s.key.len(), "device lists must be equal length");
        assert_eq!(s.pointer.len(), 5);
        // Both devices present in the build (each has a real action).
        let built = s.build();
        assert_eq!(built.len(), 2);
    }

    #[test]
    fn only_pauses_builds_nothing() {
        let mut s = Seq::default();
        s.pause(10);
        assert!(s.build().is_empty(), "a pause-only sequence emits no device");
    }

    #[test]
    fn full_payload_encodes_to_the_expected_w3c_json() {
        // The exact wire shape from the task brief: pointer move(origin) + down + up.
        let mut s = Seq::default();
        s.click(Some("EID"));
        let payload = json::obj(vec![("actions", Json::Arr(s.build()))]);
        let encoded = payload.encode();
        assert!(encoded.contains("\"type\":\"pointer\""));
        assert!(encoded.contains("\"pointerType\":\"mouse\""));
        assert!(encoded.contains("\"element-6066-11e4-a52e-4f735466cecf\":\"EID\""));
        assert!(encoded.contains("\"pointerDown\""));
        assert!(encoded.contains("\"pointerUp\""));
    }
}
