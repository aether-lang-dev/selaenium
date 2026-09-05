//! `<select>` dropdown helper — the `Select` convenience tier. Wraps a
//! `<select>` [`WebElement`] and drives it by finding and clicking its
//! `<option>` children, the same approach mainstream Selenium's `Select` (and
//! the Python reference `selenium.webdriver.support.select`) uses:
//!
//! ```no_run
//! # use selenium::{WebDriver, By, Select};
//! # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
//! let el = d.find_element(By::id("country")).unwrap();
//! Select::new(&el).unwrap().select_by_visible_text("Spain").unwrap();
//! ```
//!
//! `Select` borrows the element (which itself borrows the driver), so its
//! lifetime is tied to both. The options it returns are freshly located
//! [`WebElement`]s scoped to that same driver borrow.

use crate::{By, Result, WebDriverError, WebElement};

/// A wrapper over a `<select>` element that selects among its `<option>`
/// children. Build one with [`Select::new`].
#[derive(Debug)]
pub struct Select<'a> {
    element: &'a WebElement<'a>,
    is_multiple: bool,
}

impl<'a> Select<'a> {
    /// Wrap `element` as a `<select>`. Errors (kind `Other`) if the element is
    /// not a `<select>` tag, mirroring the mainstream `ValueError`.
    pub fn new(element: &'a WebElement<'a>) -> Result<Select<'a>> {
        let tag = element.tag_name()?.to_lowercase();
        if tag != "select" {
            return Err(WebDriverError::classify(
                0,
                format!("Select only works on <select> elements, not <{tag}>"),
            ));
        }
        // `multiple` is a boolean attribute: present (any non-"false" value) ==
        // multi-select. Mirrors the Python reference's truthiness check.
        let multi = element.get_attribute("multiple")?;
        let is_multiple = match multi {
            Some(v) => !v.is_empty() && v != "false",
            None => false,
        };
        Ok(Select { element, is_multiple })
    }

    /// Whether this is a multi-select (`multiple` attribute present).
    pub fn is_multiple(&self) -> bool {
        self.is_multiple
    }

    /// All `<option>` children, in document order.
    pub fn options(&self) -> Result<Vec<WebElement<'a>>> {
        self.element.find_elements(By::tag_name("option"))
    }

    /// The options currently selected.
    pub fn all_selected_options(&self) -> Result<Vec<WebElement<'a>>> {
        let mut out = Vec::new();
        for o in self.options()? {
            if o.is_selected()? {
                out.push(o);
            }
        }
        Ok(out)
    }

    /// The first selected option. Errors (kind `NoSuchElement`) if none is
    /// selected.
    pub fn first_selected_option(&self) -> Result<WebElement<'a>> {
        for o in self.options()? {
            if o.is_selected()? {
                return Ok(o);
            }
        }
        Err(WebDriverError::classify(17, "no option is selected".into()))
    }

    /// Select the option whose visible text equals `text`. Errors (kind
    /// `NoSuchElement`) if none matches.
    pub fn select_by_visible_text(&self, text: &str) -> Result<()> {
        let opts = self.options()?;
        let idx = self.match_index(&opts, &Criterion::Text(text))?;
        select_option(&opts[idx])
    }

    /// Select the option whose `value` attribute equals `value`. Errors (kind
    /// `NoSuchElement`) if none matches.
    pub fn select_by_value(&self, value: &str) -> Result<()> {
        let opts = self.options()?;
        let idx = self.match_index(&opts, &Criterion::Value(value))?;
        select_option(&opts[idx])
    }

    /// Read the `text`/`value` of each option (in order), then defer the choice
    /// to the pure [`find_match`] — so the option-picking rule is unit-testable
    /// without a browser. Returns the matched index or a NoSuchElement error.
    fn match_index(&self, opts: &[WebElement<'a>], criterion: &Criterion) -> Result<usize> {
        let mut infos = Vec::with_capacity(opts.len());
        for o in opts {
            infos.push(OptionInfo {
                text: o.text()?,
                value: o.get_attribute("value")?.unwrap_or_default(),
            });
        }
        find_match(&infos, criterion)
            .ok_or_else(|| WebDriverError::classify(17, criterion.miss_message()))
    }

    /// Select the option at `index` (0-based, document order). Errors (kind
    /// `NoSuchElement`) if out of range.
    pub fn select_by_index(&self, index: usize) -> Result<()> {
        let opts = self.options()?;
        let o = opts
            .get(index)
            .ok_or_else(|| WebDriverError::classify(17, format!("no option at index {index}")))?;
        select_option(o)
    }

    /// Deselect every selected option (multi-select only). Errors (kind `Other`)
    /// on a single-select, mirroring the mainstream `NotImplementedError`.
    pub fn deselect_all(&self) -> Result<()> {
        if !self.is_multiple {
            return Err(WebDriverError::classify(
                0,
                "deselect_all only makes sense on a multi-select".into(),
            ));
        }
        for o in self.options()? {
            if o.is_selected()? {
                o.click()?;
            }
        }
        Ok(())
    }
}

/// Click an option to select it, but only if it isn't already selected — a
/// second click on a selected single-select option is a no-op in the browser,
/// but on a multi-select it would toggle it off. Mirrors the reference `_select`.
fn select_option(option: &WebElement<'_>) -> Result<()> {
    if !option.is_selected()? {
        option.click()?;
    }
    Ok(())
}

// ---- pure option-matching core (browser-free, unit-testable) ----

/// A read-only snapshot of one `<option>`'s matchable fields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OptionInfo {
    pub text: String,
    pub value: String,
}

/// How to pick an option: by visible text or by `value` attribute. (Index is
/// handled directly by [`Select::select_by_index`], no scan needed.)
#[derive(Debug, Clone, Copy)]
enum Criterion<'k> {
    Text(&'k str),
    Value(&'k str),
}

impl Criterion<'_> {
    fn miss_message(&self) -> String {
        match self {
            Criterion::Text(t) => format!("no option with visible text {t:?}"),
            Criterion::Value(v) => format!("no option with value {v:?}"),
        }
    }
}

/// The first option index matching `criterion`, or `None` if none does. The pure
/// core of the `select_by_*` scan — first-match wins, in document order, exactly
/// as the Python reference iterates.
fn find_match(options: &[OptionInfo], criterion: &Criterion) -> Option<usize> {
    options.iter().position(|o| match criterion {
        Criterion::Text(t) => o.text == *t,
        Criterion::Value(v) => o.value == *v,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<OptionInfo> {
        vec![
            OptionInfo { text: "Argentina".into(), value: "ar".into() },
            OptionInfo { text: "Spain".into(), value: "es".into() },
            OptionInfo { text: "Sweden".into(), value: "se".into() },
        ]
    }

    #[test]
    fn match_by_visible_text_picks_the_right_option() {
        let opts = sample();
        assert_eq!(find_match(&opts, &Criterion::Text("Spain")), Some(1));
        assert_eq!(find_match(&opts, &Criterion::Text("Sweden")), Some(2));
    }

    #[test]
    fn match_by_value_picks_the_right_option() {
        let opts = sample();
        assert_eq!(find_match(&opts, &Criterion::Value("es")), Some(1));
        assert_eq!(find_match(&opts, &Criterion::Value("ar")), Some(0));
    }

    #[test]
    fn no_match_returns_none() {
        let opts = sample();
        assert_eq!(find_match(&opts, &Criterion::Text("Narnia")), None);
        assert_eq!(find_match(&opts, &Criterion::Value("zz")), None);
    }

    #[test]
    fn first_match_wins_in_document_order() {
        let opts = vec![
            OptionInfo { text: "Dup".into(), value: "a".into() },
            OptionInfo { text: "Dup".into(), value: "b".into() },
        ];
        assert_eq!(find_match(&opts, &Criterion::Text("Dup")), Some(0));
    }
}
