"""Relative locators, at the Selenium 4.x import path
``from selenium.webdriver.support.relative_locator import locate_with, with_tag_name``.

Mirrors mainstream Selenium-Python's ``RelativeBy`` / ``locate_with`` /
``with_tag_name`` API. A ``RelativeBy`` is passed to
``driver.find_element(...)`` / ``driver.find_elements(...)`` in place of a
(by, value) pair::

    from selenium.webdriver.support.relative_locator import locate_with, with_tag_name
    from selenium.webdriver.common.by import By

    cell = driver.find_element(locate_with(By.TAG_NAME, "td").below(header))
    els = driver.find_elements(with_tag_name("p").above({By.ID: "footer"}))

The engine's relative-locators atom anchors by CSS selector, so anchors given as
a locator dict (``{By.TAG_NAME: "h1"}``, ``{By.CSS_SELECTOR: ".x"}``, ``{By.ID:
"foo"}`` …) and the root itself resolve to CSS. Anchoring by an already-found
``WebElement`` is not supported by this engine path and raises a clear error.
"""

from __future__ import annotations

from ..common.by import By

__all__ = ["RelativeBy", "locate_with", "with_tag_name"]

# The relation names as mainstream users write them -> the engine atom's "kind".
_KIND = {
    "above": "above",
    "below": "below",
    "left": "left",
    "right": "right",
    "near": "near",
}


def _locator_to_css(locator) -> str:
    """Turn a {by: value} locator (or a bare CSS string) into a CSS selector the
    engine's relative-locators atom can query. Mirrors the strategies mainstream
    accepts as a RelativeBy root/anchor."""
    if isinstance(locator, str):
        return locator
    if not isinstance(locator, dict) or len(locator) != 1:
        raise ValueError(
            "Relative locator root/anchor must be a single {By: value} locator "
            f"or a CSS string, got: {locator!r}"
        )
    (by, value), = locator.items()
    if by in (By.CSS_SELECTOR, "css selector"):
        return value
    if by in (By.TAG_NAME, "tag name"):
        return value
    if by in (By.ID, "id"):
        # CSS id escaping is handled generically; the common case is a plain id.
        return f"#{value}"
    if by in (By.CLASS_NAME, "class name"):
        return f".{value}"
    if by in (By.NAME, "name"):
        return f"[name={value!r}]".replace("'", '"')
    raise ValueError(
        f"Relative locator does not support the {by!r} strategy for anchors; "
        "use CSS_SELECTOR, TAG_NAME, ID, CLASS_NAME or NAME"
    )


class RelativeBy:
    """A relative locator: a root selector plus spatial-relation filters against
    anchors, matching mainstream ``selenium.webdriver.support.relative_locator.RelativeBy``.

    Build one with :func:`locate_with` or :func:`with_tag_name`, chain the
    relation methods (each returns ``self`` for fluent use), then pass it to
    ``driver.find_element`` / ``driver.find_elements``."""

    def __init__(self, root=None, filters: list | None = None):
        self.root = root
        self.filters: list = list(filters) if filters else []

    def above(self, element_or_locator) -> "RelativeBy":
        return self._add("above", element_or_locator)

    def below(self, element_or_locator) -> "RelativeBy":
        return self._add("below", element_or_locator)

    def to_left_of(self, element_or_locator) -> "RelativeBy":
        return self._add("left", element_or_locator)

    def to_right_of(self, element_or_locator) -> "RelativeBy":
        return self._add("right", element_or_locator)

    def near(self, element_or_locator_distance=50) -> "RelativeBy":
        return self._add("near", element_or_locator_distance)

    def _add(self, kind: str, anchor) -> "RelativeBy":
        if anchor is None:
            raise ValueError("Cannot use None as a relative locator anchor")
        self.filters.append({"kind": kind, "anchor": anchor})
        return self

    def to_dict(self) -> dict:
        """The mainstream dict form: ``{"relative": {"root": {...}, "filters": [...]}}``."""
        return {
            "relative": {
                "root": self.root,
                "filters": [{"kind": f["kind"], "args": [f["anchor"]]} for f in self.filters],
            }
        }

    def _engine_query(self):
        """Lower this RelativeBy to the engine's ``(base_css, filters)`` pair:
        base_css is the root as CSS; filters are ``{kind, sel[, dist]}`` dicts
        with CSS-selector anchors. Raises on a WebElement anchor (unsupported by
        this engine path)."""
        from ..._webdriver import WebElement

        base_css = _locator_to_css(self.root)
        engine_filters = []
        for f in self.filters:
            anchor = f["anchor"]
            kind = _KIND[f["kind"]]
            entry = {"kind": kind}
            if kind == "near" and not isinstance(anchor, dict) and not isinstance(anchor, str):
                # near() with a bare distance keeps the previous anchor? Mainstream
                # requires an anchor; a numeric-only near is not meaningful here.
                raise ValueError("near() requires a locator anchor, not just a distance")
            if isinstance(anchor, WebElement):
                raise ValueError(
                    "This binding's relative locators anchor by CSS selector, not by a "
                    "found WebElement; pass a {By: value} locator (e.g. {By.ID: 'x'})"
                )
            entry["sel"] = _locator_to_css(anchor)
            engine_filters.append(entry)
        return base_css, engine_filters


def with_tag_name(tag_name: str) -> RelativeBy:
    """Start a relative locator rooted at ``tag_name`` (mainstream helper)."""
    if not tag_name:
        raise ValueError("tag_name can not be null")
    return RelativeBy({By.TAG_NAME: tag_name})


def locate_with(by: str, using: str) -> RelativeBy:
    """Start a relative locator rooted at the ``(by, using)`` locator
    (mainstream helper)."""
    return RelativeBy({by: using})
