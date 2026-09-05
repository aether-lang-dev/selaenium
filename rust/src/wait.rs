//! Explicit waits — the `WebDriverWait` convenience tier. Mirrors mainstream:
//! `driver.wait(timeout).until(condition)` polls `condition(driver)` until it
//! returns `Ok(true)` (or the deadline passes), and `.until_not(...)` waits for
//! it to become false. A condition is any closure taking `&WebDriver` and
//! returning `Result<bool>` — write your own, or use the [`WebDriver`]
//! convenience waits ([`wait_for_element`], [`wait_for_visible`], ...).
//!
//! Unlike a fixed sleep, a wait returns as soon as the condition holds. The poll
//! loop lives here in the binding — the engine issues single commands and holds
//! no thread, exactly as the reference `aether/webdriver.ae` waits do. On
//! timeout the wait returns a [`WebDriverError`] of kind [`ErrorKind::Timeout`].
//!
//! ```no_run
//! # use std::time::Duration;
//! # use selenium::{WebDriver, By};
//! # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
//! // General escape hatch: poll a caller-supplied predicate.
//! d.wait(Duration::from_secs(5))
//!     .until(|drv| Ok(drv.title()?.contains("Ready")))
//!     .unwrap();
//! // Convenience: block until an element is present, then use it.
//! let el = d.wait_for_element(By::id("late"), Duration::from_secs(5)).unwrap();
//! el.click().unwrap();
//! ```
//!
//! [`wait_for_element`]: WebDriver::wait_for_element
//! [`wait_for_visible`]: WebDriver::wait_for_visible
//! [`ErrorKind::Timeout`]: crate::ErrorKind::Timeout

use std::time::{Duration, Instant};

use crate::{By, ErrorKind, Result, WebDriver, WebDriverError, WebElement};

/// The default poll cadence between condition checks (mainstream's 500ms).
pub const POLL_INTERVAL: Duration = Duration::from_millis(500);

/// A configured waiter over a driver: call [`until`] / [`until_not`] with a
/// predicate. Obtain one from [`WebDriver::wait`].
///
/// [`until`]: Wait::until
/// [`until_not`]: Wait::until_not
#[derive(Debug)]
pub struct Wait<'a> {
    driver: &'a WebDriver,
    timeout: Duration,
    poll: Duration,
}

impl<'a> Wait<'a> {
    pub(crate) fn new(driver: &'a WebDriver, timeout: Duration) -> Wait<'a> {
        Wait { driver, timeout, poll: POLL_INTERVAL }
    }

    /// Override the poll cadence (default [`POLL_INTERVAL`]). A zero interval is
    /// clamped up to the default.
    pub fn poll_every(mut self, interval: Duration) -> Self {
        self.poll = if interval.is_zero() { POLL_INTERVAL } else { interval };
        self
    }

    /// Poll `condition(&driver)` until it returns `Ok(true)`; then return
    /// `Ok(())`. A [`ErrorKind::NoSuchElement`] error from the condition is
    /// swallowed and retried (a not-yet-present element should wait, not fail),
    /// as the mainstream `ignored_exceptions` default does; any other error
    /// propagates. On timeout, a [`ErrorKind::Timeout`] error.
    ///
    /// [`ErrorKind::NoSuchElement`]: crate::ErrorKind::NoSuchElement
    /// [`ErrorKind::Timeout`]: crate::ErrorKind::Timeout
    pub fn until<F>(&self, mut condition: F) -> Result<()>
    where
        F: FnMut(&WebDriver) -> Result<bool>,
    {
        let driver = self.driver;
        // truthy -> settled; ignored NoSuchElement -> keep waiting.
        poll_predicate(self.timeout, self.poll, || match condition(driver) {
            Ok(true) => Settle::Done,
            Ok(false) => Settle::Retry,
            Err(e) if e.kind == ErrorKind::NoSuchElement => Settle::Retry,
            Err(e) => Settle::Err(e),
        })
    }

    /// Poll `condition(&driver)` until it returns `Ok(false)` (or an ignored
    /// NoSuchElement, which counts as "gone"); then return `Ok(())`. On timeout,
    /// a [`ErrorKind::Timeout`] error.
    ///
    /// [`ErrorKind::Timeout`]: crate::ErrorKind::Timeout
    pub fn until_not<F>(&self, mut condition: F) -> Result<()>
    where
        F: FnMut(&WebDriver) -> Result<bool>,
    {
        let driver = self.driver;
        poll_predicate(self.timeout, self.poll, || match condition(driver) {
            Ok(false) => Settle::Done,
            Ok(true) => Settle::Retry,
            Err(e) if e.kind == ErrorKind::NoSuchElement => Settle::Done,
            Err(e) => Settle::Err(e),
        })
    }
}

/// The outcome of one poll attempt: settled (stop, success), retry (keep
/// polling), or a hard error to propagate.
enum Settle {
    Done,
    Retry,
    Err(WebDriverError),
}

/// Timeout of a wait after `timeout` elapsed.
fn timed_out(timeout: Duration) -> WebDriverError {
    WebDriverError::classify(21, format!("waited {:.3}s for condition", timeout.as_secs_f64()))
}

/// Driver-free poll loop: run `attempt` each tick until it reports `Done` (=>
/// `Ok(())`), propagate an `Err`, and on deadline return a timeout. This is the
/// timing core shared by `until` / `until_not` — no driver in sight, so it is
/// unit-testable directly. The condition is checked once before the first sleep,
/// so a zero timeout still gives one attempt.
fn poll_predicate<F>(timeout: Duration, poll: Duration, mut attempt: F) -> Result<()>
where
    F: FnMut() -> Settle,
{
    let deadline = Instant::now() + timeout;
    loop {
        match attempt() {
            Settle::Done => return Ok(()),
            Settle::Err(e) => return Err(e),
            Settle::Retry => {}
        }
        if Instant::now() >= deadline {
            return Err(timed_out(timeout));
        }
        std::thread::sleep(poll);
    }
}

impl WebDriver {
    /// Start an explicit wait with the given `timeout`. Poll cadence defaults to
    /// [`POLL_INTERVAL`]; override with [`Wait::poll_every`].
    ///
    /// ```no_run
    /// # use std::time::Duration;
    /// # use selenium::WebDriver;
    /// # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
    /// d.wait(Duration::from_secs(3))
    ///     .until(|drv| Ok(drv.title()?.contains("Done")))
    ///     .unwrap();
    /// ```
    pub fn wait(&self, timeout: Duration) -> Wait<'_> {
        Wait::new(self, timeout)
    }

    /// Block until an element matching `by` is present in the DOM; return it.
    /// (classic `until.elementLocated`.) Errors on timeout.
    pub fn wait_for_element(&self, by: By, timeout: Duration) -> Result<WebElement<'_>> {
        self.wait(timeout).poll_loop_element(|d| d.try_find(by.clone()))
    }

    /// Block until an element matching `by` is present AND displayed; return it.
    /// (classic `until.elementIsVisible`, folded with `elementLocated`.) Errors
    /// on timeout.
    pub fn wait_for_visible(&self, by: By, timeout: Duration) -> Result<WebElement<'_>> {
        self.wait(timeout).poll_loop_element(|d| match d.try_find(by.clone())? {
            Some(el) if el.is_displayed()? => Ok(Some(el)),
            _ => Ok(None),
        })
    }

    /// Block until an element matching `by` is present, displayed AND enabled
    /// (clickable); return it. Errors on timeout.
    pub fn wait_for_clickable(&self, by: By, timeout: Duration) -> Result<WebElement<'_>> {
        self.wait(timeout).poll_loop_element(|d| match d.try_find(by.clone())? {
            Some(el) if el.is_displayed()? && el.is_enabled()? => Ok(Some(el)),
            _ => Ok(None),
        })
    }

    /// Block until NO element matches `by` — it's absent/removed. (classic
    /// staleness, by locator.) Errors on timeout.
    pub fn wait_until_gone(&self, by: By, timeout: Duration) -> Result<()> {
        // "present?" true while it's still there; until_not returns once false.
        self.wait(timeout).until_not(|d| Ok(d.try_find(by.clone())?.is_some()))
    }

    /// Block until the page title equals `title`. Errors on timeout.
    pub fn wait_for_title_is(&self, title: &str, timeout: Duration) -> Result<()> {
        self.wait(timeout).until(|d| Ok(d.title()? == title))
    }

    /// Block until the page title contains `substr`. Errors on timeout.
    pub fn wait_for_title_contains(&self, substr: &str, timeout: Duration) -> Result<()> {
        self.wait(timeout).until(|d| Ok(d.title()?.contains(substr)))
    }

    /// Block until the current URL equals `url`. Errors on timeout.
    pub fn wait_for_url_is(&self, url: &str, timeout: Duration) -> Result<()> {
        self.wait(timeout).until(|d| Ok(d.current_url()? == url))
    }

    /// Block until the current URL contains `substr`. Errors on timeout.
    pub fn wait_for_url_contains(&self, substr: &str, timeout: Duration) -> Result<()> {
        self.wait(timeout).until(|d| Ok(d.current_url()?.contains(substr)))
    }

    /// `find_element` that maps a NoSuchElement miss to `Ok(None)` instead of an
    /// error — the primitive the element-returning waits poll on. Any other
    /// error (invalid selector, transport) propagates.
    fn try_find(&self, by: By) -> Result<Option<WebElement<'_>>> {
        match self.find_element(by) {
            Ok(el) => Ok(Some(el)),
            Err(e) if e.kind == ErrorKind::NoSuchElement => Ok(None),
            Err(e) => Err(e),
        }
    }
}

impl<'a> Wait<'a> {
    /// Element-returning poll loop: run `probe` each tick; the first `Ok(Some)`
    /// is returned, `Ok(None)` retries, an ignored NoSuchElement retries, any
    /// other error propagates, the deadline yields a timeout.
    fn poll_loop_element<F>(&self, mut probe: F) -> Result<WebElement<'a>>
    where
        F: FnMut(&'a WebDriver) -> Result<Option<WebElement<'a>>>,
    {
        let deadline = Instant::now() + self.timeout;
        loop {
            match probe(self.driver) {
                Ok(Some(el)) => return Ok(el),
                Ok(None) => {}
                Err(e) if e.kind == ErrorKind::NoSuchElement => {}
                Err(e) => return Err(e),
            }
            if Instant::now() >= deadline {
                return Err(timed_out(self.timeout));
            }
            std::thread::sleep(self.poll);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ErrorKind;
    use std::cell::Cell;
    use std::time::Duration;

    #[test]
    fn poll_returns_ok_when_the_condition_becomes_true() {
        // Retry twice, then settle — must succeed within the budget.
        let n = Cell::new(0);
        let out = poll_predicate(Duration::from_secs(2), Duration::from_millis(1), || {
            n.set(n.get() + 1);
            if n.get() >= 3 {
                Settle::Done
            } else {
                Settle::Retry
            }
        });
        assert!(out.is_ok(), "should settle once the condition holds");
        assert_eq!(n.get(), 3, "settled on the third attempt");
    }

    #[test]
    fn poll_times_out_with_a_timeout_error() {
        // Never settles -> a Timeout-kind error once the (tiny) budget elapses.
        let out = poll_predicate(Duration::from_millis(20), Duration::from_millis(2), || Settle::Retry);
        let err = out.unwrap_err();
        assert_eq!(err.kind, ErrorKind::Timeout);
        assert_eq!(err.code, 21);
        assert!(err.message.contains("waited"), "message: {}", err.message);
    }

    #[test]
    fn poll_propagates_a_non_ignored_error_immediately() {
        // A hard error must surface at once, not be retried until timeout.
        let attempts = Cell::new(0);
        let out = poll_predicate(Duration::from_secs(5), Duration::from_millis(1), || {
            attempts.set(attempts.get() + 1);
            Settle::Err(WebDriverError::classify(11, "invalid selector".into()))
        });
        let err = out.unwrap_err();
        assert_eq!(err.kind, ErrorKind::InvalidSelector);
        assert_eq!(attempts.get(), 1, "hard error should not retry");
    }

    #[test]
    fn poll_checks_once_even_with_a_zero_timeout() {
        // A zero budget still runs one attempt (a condition already true wins).
        let out = poll_predicate(Duration::ZERO, Duration::from_millis(1), || Settle::Done);
        assert!(out.is_ok());
    }
}
