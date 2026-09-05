//! Special keys — the W3C WebDriver Unicode private-use code points for non-text
//! keys (W3C §17.4.2). Mirrors mainstream Selenium's `Keys` (and the Python
//! reference `selenium.webdriver.common.keys`): send them through
//! [`WebElement::send_keys`] or an [`Actions`] key gesture exactly as elsewhere;
//! the values are the same code points the protocol defines, so the engine
//! forwards them unchanged.
//!
//! Each constant is a `char` (a single scalar in U+E000..=U+E03D). Append one to
//! a string, or use [`Keys::chord`] to build a modifier chord.
//!
//! [`WebElement::send_keys`]: crate::WebElement::send_keys
//! [`Actions`]: crate::Actions
//!
//! ```
//! use selenium::Keys;
//! let with_enter = format!("hello{}", Keys::ENTER);
//! assert_eq!(Keys::ENTER as u32, 0xE007);
//! ```

/// Mainstream Selenium key constants (Unicode PUA code points, W3C §17.4.2).
///
/// This is a namespace of associated `const char` values, not an instantiable
/// type — reach a key as `Keys::ENTER`.
#[non_exhaustive]
pub struct Keys;

#[allow(non_upper_case_globals)]
impl Keys {
    pub const NULL: char = '\u{E000}';
    pub const CANCEL: char = '\u{E001}';
    pub const HELP: char = '\u{E002}';
    pub const BACKSPACE: char = '\u{E003}';
    pub const BACK_SPACE: char = Keys::BACKSPACE;
    pub const TAB: char = '\u{E004}';
    pub const CLEAR: char = '\u{E005}';
    pub const RETURN: char = '\u{E006}';
    pub const ENTER: char = '\u{E007}';
    pub const SHIFT: char = '\u{E008}';
    pub const LEFT_SHIFT: char = Keys::SHIFT;
    pub const CONTROL: char = '\u{E009}';
    pub const LEFT_CONTROL: char = Keys::CONTROL;
    pub const ALT: char = '\u{E00A}';
    pub const LEFT_ALT: char = Keys::ALT;
    pub const PAUSE: char = '\u{E00B}';
    pub const ESCAPE: char = '\u{E00C}';
    pub const SPACE: char = '\u{E00D}';
    pub const PAGE_UP: char = '\u{E00E}';
    pub const PAGE_DOWN: char = '\u{E00F}';
    pub const END: char = '\u{E010}';
    pub const HOME: char = '\u{E011}';
    pub const LEFT: char = '\u{E012}';
    pub const ARROW_LEFT: char = Keys::LEFT;
    pub const UP: char = '\u{E013}';
    pub const ARROW_UP: char = Keys::UP;
    pub const RIGHT: char = '\u{E014}';
    pub const ARROW_RIGHT: char = Keys::RIGHT;
    pub const DOWN: char = '\u{E015}';
    pub const ARROW_DOWN: char = Keys::DOWN;
    pub const INSERT: char = '\u{E016}';
    pub const DELETE: char = '\u{E017}';
    pub const SEMICOLON: char = '\u{E018}';
    pub const EQUALS: char = '\u{E019}';

    pub const NUMPAD0: char = '\u{E01A}';
    pub const NUMPAD1: char = '\u{E01B}';
    pub const NUMPAD2: char = '\u{E01C}';
    pub const NUMPAD3: char = '\u{E01D}';
    pub const NUMPAD4: char = '\u{E01E}';
    pub const NUMPAD5: char = '\u{E01F}';
    pub const NUMPAD6: char = '\u{E020}';
    pub const NUMPAD7: char = '\u{E021}';
    pub const NUMPAD8: char = '\u{E022}';
    pub const NUMPAD9: char = '\u{E023}';
    pub const MULTIPLY: char = '\u{E024}';
    pub const ADD: char = '\u{E025}';
    pub const SEPARATOR: char = '\u{E026}';
    pub const SUBTRACT: char = '\u{E027}';
    pub const DECIMAL: char = '\u{E028}';
    pub const DIVIDE: char = '\u{E029}';

    pub const F1: char = '\u{E031}';
    pub const F2: char = '\u{E032}';
    pub const F3: char = '\u{E033}';
    pub const F4: char = '\u{E034}';
    pub const F5: char = '\u{E035}';
    pub const F6: char = '\u{E036}';
    pub const F7: char = '\u{E037}';
    pub const F8: char = '\u{E038}';
    pub const F9: char = '\u{E039}';
    pub const F10: char = '\u{E03A}';
    pub const F11: char = '\u{E03B}';
    pub const F12: char = '\u{E03C}';

    pub const META: char = '\u{E03D}';
    pub const COMMAND: char = '\u{E03D}';

    /// A modifier chord: `modifier` held while `text` is typed, then the sequence
    /// closed by the terminating NULL that the protocol uses to release held
    /// modifiers — e.g. `Keys::chord(Keys::CONTROL, "a")` for select-all. This is
    /// the classic `Keys.chord` helper, rendered as a single `String` you pass to
    /// [`WebElement::send_keys`].
    ///
    /// [`WebElement::send_keys`]: crate::WebElement::send_keys
    ///
    /// ```
    /// use selenium::Keys;
    /// let s = Keys::chord(Keys::CONTROL, "a");
    /// assert_eq!(s.chars().next(), Some(Keys::CONTROL));
    /// assert!(s.ends_with(Keys::NULL));
    /// ```
    pub fn chord(modifier: char, text: &str) -> String {
        let mut s = String::new();
        s.push(modifier);
        s.push_str(text);
        s.push(Keys::NULL);
        s
    }
}

#[cfg(test)]
mod tests {
    use super::Keys;

    #[test]
    fn code_points_match_the_w3c_spec() {
        // Spot-check the ones the task named, plus the range endpoints.
        assert_eq!(Keys::NULL as u32, 0xE000);
        assert_eq!(Keys::TAB as u32, 0xE004);
        assert_eq!(Keys::ENTER as u32, 0xE007);
        assert_eq!(Keys::ESCAPE as u32, 0xE00C);
        assert_eq!(Keys::DIVIDE as u32, 0xE029);
        assert_eq!(Keys::F1 as u32, 0xE031);
        assert_eq!(Keys::F12 as u32, 0xE03C);
        assert_eq!(Keys::META as u32, 0xE03D);
    }

    #[test]
    fn every_key_is_in_the_pua_block() {
        // U+E000..=U+E03D is the W3C key range; nothing may fall outside it.
        for k in [
            Keys::NULL, Keys::CANCEL, Keys::HELP, Keys::BACKSPACE, Keys::TAB, Keys::CLEAR,
            Keys::RETURN, Keys::ENTER, Keys::SHIFT, Keys::CONTROL, Keys::ALT, Keys::PAUSE,
            Keys::ESCAPE, Keys::SPACE, Keys::PAGE_UP, Keys::PAGE_DOWN, Keys::END, Keys::HOME,
            Keys::LEFT, Keys::UP, Keys::RIGHT, Keys::DOWN, Keys::INSERT, Keys::DELETE,
            Keys::SEMICOLON, Keys::EQUALS, Keys::NUMPAD0, Keys::NUMPAD9, Keys::MULTIPLY,
            Keys::ADD, Keys::SEPARATOR, Keys::SUBTRACT, Keys::DECIMAL, Keys::DIVIDE,
            Keys::F1, Keys::F12, Keys::META, Keys::COMMAND,
        ] {
            let cp = k as u32;
            assert!((0xE000..=0xE03D).contains(&cp), "{cp:#X} out of PUA key range");
        }
    }

    #[test]
    fn aliases_agree_with_their_canonical_key() {
        assert_eq!(Keys::BACK_SPACE, Keys::BACKSPACE);
        assert_eq!(Keys::LEFT_SHIFT, Keys::SHIFT);
        assert_eq!(Keys::LEFT_CONTROL, Keys::CONTROL);
        assert_eq!(Keys::LEFT_ALT, Keys::ALT);
        assert_eq!(Keys::ARROW_LEFT, Keys::LEFT);
        assert_eq!(Keys::ARROW_UP, Keys::UP);
        assert_eq!(Keys::ARROW_RIGHT, Keys::RIGHT);
        assert_eq!(Keys::ARROW_DOWN, Keys::DOWN);
        assert_eq!(Keys::COMMAND, Keys::META);
    }

    #[test]
    fn chord_holds_modifier_then_releases_with_null() {
        let s = Keys::chord(Keys::CONTROL, "a");
        let chars: Vec<char> = s.chars().collect();
        assert_eq!(chars[0], Keys::CONTROL);
        assert_eq!(chars[1], 'a');
        assert_eq!(chars[2], Keys::NULL);
        assert_eq!(chars.len(), 3);
    }
}
