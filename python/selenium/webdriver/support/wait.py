"""Explicit waits, at the Selenium 4.x import path
``from selenium.webdriver.support.wait import WebDriverWait``.

Mirrors mainstream: ``WebDriverWait(driver, 10).until(condition)`` polls
``condition(driver)`` until it returns a truthy value (or raises), and
``.until_not(condition)`` waits for it to stop being truthy. A condition is any
callable taking the driver — the ``expected_conditions`` helpers, or your own
lambda. Poll cadence and timeout match the mainstream defaults.

Unlike a fixed ``time.sleep``, this returns as soon as the condition holds. The
loop lives in the binding (the engine issues single commands and holds no
thread), exactly as the reference ``aether/webdriver.ae`` waits do.
"""
from __future__ import annotations

import time
from typing import Callable, TypeVar

from ..._webdriver import TimeoutException, NoSuchElementException, StaleElementReferenceException

POLL_FREQUENCY = 0.5  # seconds between polls — mainstream default
IGNORED_EXCEPTIONS = (NoSuchElementException,)

T = TypeVar("T")


class WebDriverWait:
    def __init__(self, driver, timeout: float, poll_frequency: float = POLL_FREQUENCY,
                 ignored_exceptions=None):
        """``timeout`` seconds (mainstream uses seconds, not ms). ``driver`` is
        passed to each condition call. ``ignored_exceptions`` are swallowed
        during polling (a not-yet-present element should retry, not raise)."""
        self._driver = driver
        self._timeout = float(timeout)
        self._poll = poll_frequency if poll_frequency > 0 else POLL_FREQUENCY
        ignored = list(IGNORED_EXCEPTIONS)
        if ignored_exceptions is not None:
            try:
                ignored.extend(iter(ignored_exceptions))
            except TypeError:
                ignored.append(ignored_exceptions)
        self._ignored = tuple(ignored)

    def until(self, method: Callable[..., T], message: str = "") -> T:
        """Poll ``method(driver)`` until it returns something truthy; return it.
        Raise ``TimeoutException`` if the deadline passes first."""
        end = time.monotonic() + self._timeout
        last_exc = None
        while True:
            try:
                value = method(self._driver)
                if value:
                    return value
            except self._ignored as exc:
                last_exc = exc
            if time.monotonic() > end:
                break
            time.sleep(self._poll)
        raise TimeoutException(message or _timeout_msg(self._timeout, last_exc))

    def until_not(self, method: Callable[..., T], message: str = "") -> bool:
        """Poll until ``method(driver)`` returns falsy (or raises an ignored
        exception); return ``True``. Raise ``TimeoutException`` on timeout."""
        end = time.monotonic() + self._timeout
        while True:
            try:
                value = method(self._driver)
                if not value:
                    return True
            except self._ignored:
                return True
            if time.monotonic() > end:
                break
            time.sleep(self._poll)
        raise TimeoutException(message or _timeout_msg(self._timeout, None))


def _timeout_msg(timeout: float, last_exc) -> str:
    base = f"waited {timeout:g}s for condition"
    if last_exc is not None:
        return f"{base} (last error: {type(last_exc).__name__}: {last_exc})"
    return base


__all__ = ["WebDriverWait"]
