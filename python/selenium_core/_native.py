"""Raw ctypes surface over the native Selenium core library.

1:1 with the ``aether_sel_embed_*`` C ABI exported by the in-repo
``core/embed.ae`` (built on the ``core/selenium_core.ae`` engine). This module
owns library location/loading, prototype declarations, and the string-ownership
helper.

Handle-based contract (matching the engine side): N independent WebDriver
sessions can run concurrently in one process, each keyed by its own handle. The
lifecycle, execute, and result-accessor calls all take that handle.

Returned ``char*`` values are caller-owned and NUL-terminated; copy them to a
Python ``str`` and free them with ``aether_sel_embed_free_string`` (see
:func:`take_string`).

Loading is LAZY: the shared library is opened on first native use, not at
import — so a caller can pin an explicit path first via :func:`configure`
(``native_lib=``) and have it win over discovery. If no explicit path is set,
discovery is the convenience default: the package's own bundled ``native/``
directory, with ``SELENIUM_CORE_LIB`` as an env override for development.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import sys

# Native library base name (no "lib" prefix / extension).
_LIB = "selenium_core"

_explicit_path: str | None = None
_lib: ctypes.CDLL | None = None
_loaded = False


def configure(path: str | None) -> None:
    """Pin an explicit path to the native library, used at first load.

    Backs the first-class ``native_lib=`` argument. No-op once the library has
    already loaded; set it before the first native call. ``None`` leaves
    discovery in charge.
    """
    global _explicit_path
    if path:
        _explicit_path = path


def _file_name() -> str:
    if sys.platform == "win32":
        return f"{_LIB}.dll"
    if sys.platform == "darwin":
        return f"lib{_LIB}.dylib"
    return f"lib{_LIB}.so"


def _candidate_paths():
    """Yield candidate paths, in resolution order:

    1. explicit path pinned via ``native_lib=`` / :func:`configure`;
    2. ``SELENIUM_CORE_LIB`` (env override — a fresh ``ae build`` artifact);
    3. the package's bundled ``native/`` directory (a shipped wheel's ``.so``);
    4. the bare file name (let the OS loader / ``find_library`` try).
    """
    if _explicit_path:
        yield _explicit_path

    override = os.environ.get("SELENIUM_CORE_LIB")
    if override:
        yield override

    here = os.path.dirname(os.path.abspath(__file__))
    yield os.path.join(here, "native", _file_name())


def _load_library() -> ctypes.CDLL:
    last_err: OSError | None = None
    for candidate in _candidate_paths():
        if candidate and os.path.isfile(candidate):
            try:
                return ctypes.CDLL(candidate)
            except OSError as exc:  # pragma: no cover - platform specific
                last_err = exc

    for name in (_file_name(), ctypes.util.find_library(_LIB)):
        if not name:
            continue
        try:
            return ctypes.CDLL(name)
        except OSError as exc:  # pragma: no cover - platform specific
            last_err = exc

    raise OSError(
        f"could not load native Selenium core library '{_file_name()}'. Build it "
        f"with `aeb core/.build.ae`, pass native_lib=<path>, or set "
        f"SELENIUM_CORE_LIB." + (f" (last error: {last_err})" if last_err else "")
    )


def _decl(name, restype, argtypes):
    fn = getattr(_lib, name)
    fn.restype = restype
    fn.argtypes = argtypes
    return fn


# char*-returning functions use c_void_p (NOT c_char_p, which auto-converts to
# bytes and drops the pointer we must free).
_CSTR = ctypes.c_void_p
_HANDLE = ctypes.c_void_p


def _ensure_loaded() -> None:
    """Open the shared library (once) and bind every prototype into this module.

    Idempotent; triggered lazily by :func:`__getattr__`.
    """
    global _lib, _loaded
    if _loaded:
        return
    _lib = _load_library()
    g = globals()

    # ---- lifecycle ----
    g["open"] = _decl("aether_sel_embed_open", _HANDLE, [ctypes.c_char_p])
    g["close"] = _decl("aether_sel_embed_close", None, [_HANDLE])

    # ---- workhorse ----
    g["execute"] = _decl(
        "aether_sel_embed_execute", ctypes.c_int,
        [_HANDLE, ctypes.c_char_p, ctypes.c_char_p],
    )

    # ---- result accessors ----
    g["last_value"] = _decl("aether_sel_embed_last_value", _CSTR, [_HANDLE])
    g["last_status"] = _decl("aether_sel_embed_last_status", ctypes.c_int, [_HANDLE])
    g["last_error_code"] = _decl("aether_sel_embed_last_error_code", ctypes.c_int, [_HANDLE])
    g["last_error"] = _decl("aether_sel_embed_last_error", _CSTR, [_HANDLE])
    g["session_id"] = _decl("aether_sel_embed_session_id", _CSTR, [_HANDLE])

    # ---- pure helpers ----
    g["by_locator"] = _decl(
        "aether_sel_embed_by_locator", _CSTR, [ctypes.c_char_p, ctypes.c_char_p]
    )
    g["route"] = _decl("aether_sel_embed_route", _CSTR, [ctypes.c_char_p])
    g["build_request"] = _decl(
        "aether_sel_embed_build_request", _CSTR,
        [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p],
    )
    g["error_code"] = _decl("aether_sel_embed_error_code", ctypes.c_int, [ctypes.c_char_p])

    # ---- atom-backed commands (isDisplayed/getAttribute/getText, run in-page) ----
    g["execute_atom"] = _decl(
        "aether_sel_embed_execute_atom", ctypes.c_int,
        [_HANDLE, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p],
    )
    g["is_displayed"] = _decl("aether_sel_embed_is_displayed", ctypes.c_int, [_HANDLE, ctypes.c_char_p])
    g["get_attribute"] = _decl(
        "aether_sel_embed_get_attribute", ctypes.c_int, [_HANDLE, ctypes.c_char_p, ctypes.c_char_p]
    )
    g["atom_str_arg"] = _decl("aether_sel_embed_atom_str_arg", _CSTR, [ctypes.c_char_p])
    g["find_relative"] = _decl(
        "aether_sel_embed_find_relative", ctypes.c_int, [_HANDLE, ctypes.c_char_p, ctypes.c_char_p]
    )

    # ---- WebDriver-BiDi (over the session's webSocketUrl) ----
    # An opaque BiDi channel handle, independent of the W3C session handle.
    g["bidi_open"] = _decl("aether_sel_embed_bidi_open", _HANDLE, [ctypes.c_char_p])
    g["bidi_close"] = _decl("aether_sel_embed_bidi_close", None, [_HANDLE])
    g["bidi_send"] = _decl(
        "aether_sel_embed_bidi_send", ctypes.c_int,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p],
    )
    g["bidi_pump"] = _decl("aether_sel_embed_bidi_pump", ctypes.c_int, [_HANDLE, ctypes.c_int])
    g["bidi_fd"] = _decl("aether_sel_embed_bidi_fd", ctypes.c_int, [_HANDLE])
    g["bidi_poll_reply"] = _decl("aether_sel_embed_bidi_poll_reply", _CSTR, [_HANDLE, ctypes.c_int])
    g["bidi_poll_event"] = _decl("aether_sel_embed_bidi_poll_event", _CSTR, [_HANDLE])
    g["bidi_lost_events"] = _decl("aether_sel_embed_bidi_lost_events", ctypes.c_int, [_HANDLE])
    g["bidi_cancel"] = _decl("aether_sel_embed_bidi_cancel", None, [_HANDLE, ctypes.c_int])
    g["bidi_subscribe"] = _decl(
        "aether_sel_embed_bidi_subscribe", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_unsubscribe"] = _decl(
        "aether_sel_embed_bidi_unsubscribe", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_wait_event"] = _decl(
        "aether_sel_embed_bidi_wait_event", _CSTR,
        [_HANDLE, ctypes.c_char_p, ctypes.c_int],
    )
    # typed BiDi convenience commands
    g["bidi_get_tree"] = _decl(
        "aether_sel_embed_bidi_get_tree", _CSTR, [_HANDLE, ctypes.c_int, ctypes.c_int]
    )
    g["bidi_script_evaluate"] = _decl(
        "aether_sel_embed_bidi_script_evaluate", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_navigate"] = _decl(
        "aether_sel_embed_bidi_navigate", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int],
    )
    # network interception
    g["bidi_network_add_intercept"] = _decl(
        "aether_sel_embed_bidi_network_add_intercept", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_network_remove_intercept"] = _decl(
        "aether_sel_embed_bidi_network_remove_intercept", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_network_continue_request"] = _decl(
        "aether_sel_embed_bidi_network_continue_request", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
    )
    g["bidi_network_fail_request"] = _decl(
        "aether_sel_embed_bidi_network_fail_request", _CSTR,
        [_HANDLE, ctypes.c_int, ctypes.c_char_p, ctypes.c_int],
    )

    # ---- string ownership ----
    g["free_string"] = _decl("aether_sel_embed_free_string", None, [ctypes.c_void_p])

    _loaded = True


def __getattr__(name: str):
    """PEP 562 lazy hook: first access to a native symbol loads the library."""
    if not _loaded and not name.startswith("_"):
        _ensure_loaded()
        if name in globals():
            return globals()[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def take_string(ptr) -> str:
    """Copy a caller-owned native ``char*`` into a Python ``str`` and free it.

    Returns ``""`` for a NULL pointer.
    """
    if not ptr:
        return ""
    _ensure_loaded()
    try:
        return ctypes.string_at(ptr).decode("utf-8")
    finally:
        free_string(ctypes.c_void_p(ptr))  # noqa: F821 (bound lazily)


def encode(value: str) -> bytes:
    """Encode a Python str to UTF-8 bytes for a ``c_char_p`` argument."""
    return value.encode("utf-8")
