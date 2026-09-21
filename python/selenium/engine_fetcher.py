"""Fetch the prebuilt pure-Aether engine (``libselenium_core``) from the
project's GitHub releases and cache it, so a Python dev never needs the Aether
toolchain: ``pip install selenium`` ships no engine, then ONE explicit command

    python -m selenium.fetch_engine        # or selenium.webdriver.fetch_engine()

downloads the right ``.so``/``.dylib``/``.dll`` for this OS+arch, verifies its
published ``.sha256``, and drops it in the per-user cache where :mod:`_native`'s
loader already looks. Explicit, one-time, opt-in — no download happens behind
the dev's back at ``import`` or ``pip install`` time.

Stdlib only (``urllib`` + ``hashlib`` + ``os``/``platform``/``sysconfig``),
matching the binding's zero-runtime-dependency contract.
"""

from __future__ import annotations

import hashlib
import os
import platform
import sysconfig
import urllib.request

# The engine release this binding targets. It tracks the gh-release TAG of the
# shared engine (NOT the binding's own ``__version__``) — that is the tag whose
# assets this fetcher downloads. Bump it when the binding is re-glued to a newer
# engine.
ENGINE_VERSION = "v0.9.0"

REPO = "aether-lang-dev/selaenium"

# ``GET https://github.com/<repo>/releases/download/<tag>/<asset>`` — the
# public, unauthenticated asset URL ``gh release create`` publishes to.
RELEASE_BASE = f"https://github.com/{REPO}/releases/download"


class FetchError(Exception):
    """Raised when the engine could not be downloaded or verified."""


def fetch(tag: str = ENGINE_VERSION, force: bool = False) -> str:
    """Download (unless already cached + verified) the engine for this platform
    and return the absolute path to the cached library.

    Idempotent: a present, checksum-matching cached copy is returned without a
    network call. ``tag`` overrides :data:`ENGINE_VERSION` (e.g. to pin an older
    engine); ``force`` re-fetches.
    """
    dest = cached_path(tag)
    want = _expected_sha(tag)
    if not force and os.path.isfile(dest) and _checksum_ok(dest, want):
        return dest

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    asset = asset_name(tag)
    body = _download(f"{RELEASE_BASE}/{tag}/{asset}")

    got = hashlib.sha256(body).hexdigest()
    if want and got != want:
        raise FetchError(f"checksum mismatch for {asset}: expected {want}, got {got}")

    # Write atomically so a half-written file is never left where the loader
    # would try to dlopen it.
    tmp = f"{dest}.{os.getpid()}.part"
    with open(tmp, "wb") as fh:
        fh.write(body)
    os.replace(tmp, dest)
    return dest


def cached_path(tag: str = ENGINE_VERSION) -> str:
    """The absolute path the fetched engine is cached at (whether or not it
    exists yet) — exactly the path :func:`_native._candidate_paths` adds, so a
    fetched engine is found on the next load with no further config.
    """
    return os.path.join(cache_dir(), tag, library_filename())


def cache_dir() -> str:
    """``$XDG_CACHE_HOME/selaenium`` (or the OS default): ``~/.cache/selaenium``
    on Linux, ``~/Library/Caches/selaenium`` on macOS,
    ``%LOCALAPPDATA%\\selaenium`` on Windows. Kept separate from the package so
    it survives pip upgrades/reinstalls.
    """
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg:
        base = xdg
    elif _system() == "windows":
        base = os.environ.get("LOCALAPPDATA") or os.path.join(
            os.path.expanduser("~"), "AppData", "Local"
        )
    elif _system() == "macos":
        base = os.path.join(os.path.expanduser("~"), "Library", "Caches")
    else:
        base = os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "selaenium")


def asset_name(tag: str = ENGINE_VERSION) -> str:
    """The gh-release asset for this platform, e.g.
    ``libselenium_core-v0.8.0-linux-x86_64.so``.
    """
    return f"libselenium_core-{tag}-{os_tag()}-{arch_tag()}.{ext()}"


def library_filename() -> str:
    """The local filename the loader looks for (bare ``libselenium_core.<ext>``,
    no tag/platform — the cache dir already keys by tag).
    """
    if _system() == "windows":
        return "selenium_core.dll"
    if _system() == "macos":
        return "libselenium_core.dylib"
    return "libselenium_core.so"


# --- platform mapping (matches release/build.sh's artifact names) ---


def os_tag() -> str:
    system = _system()
    if system in ("linux", "macos", "windows"):
        return system
    raise FetchError(f"unsupported OS for a prebuilt engine: {platform.system()!r}")


def arch_tag() -> str:
    machine = platform.machine().lower()
    if machine in ("x86_64", "x64", "amd64"):
        return "x86_64"
    if machine in ("arm64", "aarch64"):
        return "arm64"
    raise FetchError(f"unsupported CPU for a prebuilt engine: {platform.machine()!r}")


def ext() -> str:
    if _system() == "windows":
        return "dll"
    if _system() == "macos":
        return "dylib"
    return "so"


# --- helpers ---


def _system() -> str:
    """Normalize ``platform.system()`` to the release os token.

    ``sysconfig`` is consulted as a fallback so a frozen/embedded interpreter
    that reports an empty ``platform.system()`` still maps correctly.
    """
    system = platform.system().lower()
    if not system:
        system = sysconfig.get_platform().lower()
    if system.startswith("linux"):
        return "linux"
    if system.startswith("darwin") or "macos" in system:
        return "macos"
    if system.startswith("win") or "mingw" in system or "cygwin" in system:
        return "windows"
    return system


def _expected_sha(tag: str = ENGINE_VERSION) -> str | None:
    """Fetch the published ``<asset>.sha256`` sidecar (a ``"<hex>  <name>"``
    line) and return the hex, or ``None`` if the sidecar can't be fetched — the
    caller then downloads without a checksum gate rather than failing hard, but
    a present sidecar is always enforced.
    """
    try:
        line = _download(f"{RELEASE_BASE}/{tag}/{asset_name(tag)}.sha256")
    except FetchError:
        return None
    text = line.decode("utf-8", "replace").strip()
    return text.split()[0] if text else None


def _checksum_ok(path: str, want: str | None) -> bool:
    if not want:
        return False
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest() == want


def _download(url: str) -> bytes:
    """GET a URL, following GitHub's redirect to the asset CDN (``urllib``
    follows redirects by default). Binary-safe.
    """
    req = urllib.request.Request(url, headers={"User-Agent": "selaenium-python"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:  # noqa: S310 (https)
            return resp.read()
    except urllib.error.HTTPError as exc:
        raise FetchError(f"GET {url} -> {exc.code} {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise FetchError(f"GET {url} failed: {exc.reason}") from exc
