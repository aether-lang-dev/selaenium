"""Fluent action builder, at the Selenium 4.x import path
``from selenium.webdriver.common.action_chains import ActionChains``.

Mirrors mainstream: queue gestures with chained calls, then ``.perform()``::

    from selenium.webdriver.common.action_chains import ActionChains
    ActionChains(driver).move_to_element(menu).click(item).perform()

Each call appends to a W3C actions sequence (pointer + key virtual devices);
``perform()`` posts the whole sequence in one ``actions`` command. This is the
same wire shape the reference ``aether/webdriver.ae`` action_* helpers emit.
"""
from __future__ import annotations

from typing import Optional

from ..._webdriver import WebElement

_W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"


class ScrollOrigin:
    """Where a wheel scroll originates: the center of an element, or the
    viewport's upper-left, plus x/y offsets. Mirrors mainstream Selenium's
    ``ScrollOrigin`` (used by :meth:`ActionChains.scroll_from_origin`)."""

    def __init__(self, origin, x_offset: int, y_offset: int) -> None:
        self._origin = origin
        self._x_offset = x_offset
        self._y_offset = y_offset

    @classmethod
    def from_element(cls, element: WebElement, x_offset: int = 0, y_offset: int = 0) -> "ScrollOrigin":
        return cls(element, x_offset, y_offset)

    @classmethod
    def from_viewport(cls, x_offset: int = 0, y_offset: int = 0) -> "ScrollOrigin":
        return cls("viewport", x_offset, y_offset)

    @property
    def origin(self):
        return self._origin

    @property
    def x_offset(self) -> int:
        return self._x_offset

    @property
    def y_offset(self) -> int:
        return self._y_offset


class ActionChains:
    def __init__(self, driver, duration: int = 250):
        self._driver = driver
        self._duration = duration
        self._pointer: list = []  # pointer device actions
        self._key: list = []      # key device actions
        self._wheel: list = []    # wheel device actions

    # ---- pointer gestures ----

    def move_to_element(self, element: WebElement) -> "ActionChains":
        self._pointer.append({
            "type": "pointerMove", "duration": 100, "x": 0, "y": 0,
            "origin": {_W3C_ELEMENT_KEY: element.id},
        })
        self._sync_lengths()
        return self

    def click(self, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.move_to_element(element)
        self._pointer.append({"type": "pointerDown", "button": 0})
        self._pointer.append({"type": "pointerUp", "button": 0})
        self._sync_lengths()
        return self

    def context_click(self, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.move_to_element(element)
        self._pointer.append({"type": "pointerDown", "button": 2})
        self._pointer.append({"type": "pointerUp", "button": 2})
        self._sync_lengths()
        return self

    def double_click(self, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.move_to_element(element)
        for _ in range(2):
            self._pointer.append({"type": "pointerDown", "button": 0})
            self._pointer.append({"type": "pointerUp", "button": 0})
        self._sync_lengths()
        return self

    def click_and_hold(self, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.move_to_element(element)
        self._pointer.append({"type": "pointerDown", "button": 0})
        self._sync_lengths()
        return self

    def release(self, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.move_to_element(element)
        self._pointer.append({"type": "pointerUp", "button": 0})
        self._sync_lengths()
        return self

    def drag_and_drop(self, source: WebElement, target: WebElement) -> "ActionChains":
        self.click_and_hold(source)
        self.move_to_element(target)
        self.release()
        return self

    def drag_and_drop_by_offset(self, source: WebElement, xoffset: int, yoffset: int) -> "ActionChains":
        """Press on ``source``, move by an (x, y) offset, and release."""
        self.click_and_hold(source)
        self.move_by_offset(xoffset, yoffset)
        self.release()
        return self

    def move_by_offset(self, xoffset: int, yoffset: int) -> "ActionChains":
        """Move the pointer by an offset from its current position."""
        self._pointer.append({
            "type": "pointerMove", "duration": self._duration,
            "x": int(xoffset), "y": int(yoffset), "origin": "pointer",
        })
        self._sync_lengths()
        return self

    def move_to_element_with_offset(self, to_element: WebElement, xoffset: int, yoffset: int) -> "ActionChains":
        """Move the pointer to an offset from the top-left of ``to_element``."""
        self._pointer.append({
            "type": "pointerMove", "duration": self._duration,
            "x": int(xoffset), "y": int(yoffset),
            "origin": {_W3C_ELEMENT_KEY: to_element.id},
        })
        self._sync_lengths()
        return self

    # ---- wheel gestures ----

    def scroll_to_element(self, element: WebElement) -> "ActionChains":
        """Scroll the viewport until ``element`` is in view (origin = element)."""
        self._wheel.append({
            "type": "scroll", "x": 0, "y": 0, "deltaX": 0, "deltaY": 0,
            "duration": 0, "origin": {_W3C_ELEMENT_KEY: element.id},
        })
        self._sync_lengths()
        return self

    def scroll_by_amount(self, delta_x: int, delta_y: int) -> "ActionChains":
        """Scroll the viewport by (delta_x, delta_y) from its top-left."""
        self._wheel.append({
            "type": "scroll", "x": 0, "y": 0,
            "deltaX": int(delta_x), "deltaY": int(delta_y),
            "duration": 0, "origin": "viewport",
        })
        self._sync_lengths()
        return self

    def scroll_from_origin(self, scroll_origin: "ScrollOrigin", delta_x: int, delta_y: int) -> "ActionChains":
        """Scroll by (delta_x, delta_y) from a :class:`ScrollOrigin` (element
        center or viewport upper-left) plus that origin's offsets."""
        if not isinstance(scroll_origin, ScrollOrigin):
            raise TypeError(f"Expected object of type ScrollOrigin, got: {type(scroll_origin)}")
        origin = scroll_origin.origin
        if isinstance(origin, WebElement):
            origin = {_W3C_ELEMENT_KEY: origin.id}
        self._wheel.append({
            "type": "scroll",
            "x": int(scroll_origin.x_offset), "y": int(scroll_origin.y_offset),
            "deltaX": int(delta_x), "deltaY": int(delta_y),
            "duration": 0, "origin": origin,
        })
        self._sync_lengths()
        return self

    # ---- key gestures ----

    def key_down(self, key: str, element: Optional[WebElement] = None) -> "ActionChains":
        if element is not None:
            self.click(element)
        self._key.append({"type": "keyDown", "value": key})
        self._sync_lengths()
        return self

    def key_up(self, key: str, element: Optional[WebElement] = None) -> "ActionChains":
        self._key.append({"type": "keyUp", "value": key})
        self._sync_lengths()
        return self

    def send_keys(self, *keys: str) -> "ActionChains":
        for chunk in keys:
            for ch in chunk:
                self._key.append({"type": "keyDown", "value": ch})
                self._key.append({"type": "keyUp", "value": ch})
        self._sync_lengths()
        return self

    def send_keys_to_element(self, element: WebElement, *keys_to_send: str) -> "ActionChains":
        """Click ``element`` to focus it, then type the given keys into it."""
        self.click(element)
        self.send_keys(*keys_to_send)
        return self

    def pause(self, seconds: float) -> "ActionChains":
        ms = int(seconds * 1000)
        self._pointer.append({"type": "pause", "duration": ms})
        self._sync_lengths()
        return self

    # ---- terminal ----

    def perform(self) -> None:
        actions = []
        if any(a["type"] != "pause" for a in self._pointer):
            actions.append({
                "type": "pointer", "id": "mouse",
                "parameters": {"pointerType": "mouse"},
                "actions": self._pointer,
            })
        if any(a["type"] != "pause" for a in self._key):
            actions.append({
                "type": "key", "id": "keyboard", "actions": self._key,
            })
        if any(a["type"] != "pause" for a in self._wheel):
            actions.append({
                "type": "wheel", "id": "wheel", "actions": self._wheel,
            })
        if actions:
            self._driver._execute("actions", {"actions": actions})

    def reset_actions(self) -> None:
        """Clear the queued actions on every device (mainstream: also releases
        remote-end state). Here it resets the locally-built sequences."""
        self._pointer = []
        self._key = []
        self._wheel = []
        try:
            self._driver._execute("clearActions")
        except Exception:
            pass

    def _sync_lengths(self) -> None:
        """W3C requires every device's action list to be the same length; pad
        the shorter with pauses so gestures on one device don't desync ticks."""
        n = max(len(self._pointer), len(self._key), len(self._wheel))
        while len(self._pointer) < n:
            self._pointer.append({"type": "pause", "duration": 0})
        while len(self._key) < n:
            self._key.append({"type": "pause", "duration": 0})
        while len(self._wheel) < n:
            self._wheel.append({"type": "pause", "duration": 0})


__all__ = ["ActionChains", "ScrollOrigin"]
