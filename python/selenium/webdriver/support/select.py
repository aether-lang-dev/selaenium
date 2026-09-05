"""``<select>`` dropdown helper, at the Selenium 4.x import path
``from selenium.webdriver.support.select import Select``.

Wraps a ``<select>`` WebElement and drives it by finding and clicking its
``<option>`` children — the same approach mainstream Selenium's ``Select`` uses::

    from selenium.webdriver.support.select import Select
    Select(driver.find_element(By.ID, "country")).select_by_visible_text("Spain")
"""
from __future__ import annotations

from typing import List

from ..._webdriver import WebElement, NoSuchElementException
from ..common.by import By


class Select:
    def __init__(self, element: WebElement):
        tag = element.tag_name.lower()
        if tag != "select":
            raise ValueError(f"Select only works on <select> elements, not <{tag}>")
        self._el = element
        multi = element.get_attribute("multiple")
        self.is_multiple = bool(multi) and multi != "false"

    @property
    def options(self) -> List[WebElement]:
        return self._el.find_elements(By.TAG_NAME, "option")

    @property
    def all_selected_options(self) -> List[WebElement]:
        return [o for o in self.options if o.is_selected()]

    @property
    def first_selected_option(self) -> WebElement:
        for o in self.options:
            if o.is_selected():
                return o
        raise NoSuchElementException("no option is selected")

    def select_by_visible_text(self, text: str) -> None:
        for o in self.options:
            if o.text == text:
                self._select(o)
                return
        raise NoSuchElementException(f"no option with visible text {text!r}")

    def select_by_value(self, value: str) -> None:
        for o in self.options:
            if o.get_attribute("value") == value:
                self._select(o)
                return
        raise NoSuchElementException(f"no option with value {value!r}")

    def select_by_index(self, index: int) -> None:
        opts = self.options
        if index < 0 or index >= len(opts):
            raise NoSuchElementException(f"no option at index {index}")
        self._select(opts[index])

    def deselect_all(self) -> None:
        if not self.is_multiple:
            raise NotImplementedError("deselect_all only makes sense on a multi-select")
        for o in self.options:
            if o.is_selected():
                o.click()

    def _select(self, option: WebElement) -> None:
        if not option.is_selected():
            option.click()


__all__ = ["Select"]
