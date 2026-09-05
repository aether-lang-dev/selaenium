"""Special keys, at the Selenium 4.x import path
``from selenium.webdriver.common.keys import Keys``.

These are the W3C WebDriver Unicode private-use code points for non-text keys.
Send them through ``element.send_keys(Keys.ENTER)`` exactly as in mainstream
Selenium; the values are the same code points the protocol defines, so the
engine forwards them unchanged.
"""


class Keys:
    """Mainstream Selenium key constants (Unicode PUA code points, W3C §17.4.2)."""

    NULL = ""
    CANCEL = ""
    HELP = ""
    BACKSPACE = ""
    BACK_SPACE = BACKSPACE
    TAB = ""
    CLEAR = ""
    RETURN = ""
    ENTER = ""
    SHIFT = ""
    LEFT_SHIFT = SHIFT
    CONTROL = ""
    LEFT_CONTROL = CONTROL
    ALT = ""
    LEFT_ALT = ALT
    PAUSE = ""
    ESCAPE = ""
    SPACE = ""
    PAGE_UP = ""
    PAGE_DOWN = ""
    END = ""
    HOME = ""
    LEFT = ""
    ARROW_LEFT = LEFT
    UP = ""
    ARROW_UP = UP
    RIGHT = ""
    ARROW_RIGHT = RIGHT
    DOWN = ""
    ARROW_DOWN = DOWN
    INSERT = ""
    DELETE = ""
    SEMICOLON = ""
    EQUALS = ""

    NUMPAD0 = ""
    NUMPAD1 = ""
    NUMPAD2 = ""
    NUMPAD3 = ""
    NUMPAD4 = ""
    NUMPAD5 = ""
    NUMPAD6 = ""
    NUMPAD7 = ""
    NUMPAD8 = ""
    NUMPAD9 = ""
    MULTIPLY = ""
    ADD = ""
    SEPARATOR = ""
    SUBTRACT = ""
    DECIMAL = ""
    DIVIDE = ""

    F1 = ""
    F2 = ""
    F3 = ""
    F4 = ""
    F5 = ""
    F6 = ""
    F7 = ""
    F8 = ""
    F9 = ""
    F10 = ""
    F11 = ""
    F12 = ""

    META = ""
    COMMAND = ""


__all__ = ["Keys"]
