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


class ActionChains:
    def __init__(self, driver):
        self._driver = driver
        self._pointer: list = []  # pointer device actions
        self._key: list = []      # key device actions

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
        if actions:
            self._driver._execute("actions", {"actions": actions})

    def _sync_lengths(self) -> None:
        """W3C requires every device's action list to be the same length; pad
        the shorter with pauses so gestures on one device don't desync ticks."""
        n = max(len(self._pointer), len(self._key))
        while len(self._pointer) < n:
            self._pointer.append({"type": "pause", "duration": 0})
        while len(self._key) < n:
            self._key.append({"type": "pause", "duration": 0})


__all__ = ["ActionChains"]
