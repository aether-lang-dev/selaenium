"""Unit test for the engine fetcher — the ``python -m selenium.fetch_engine``
machinery that lets a Python dev get the prebuilt pure-Aether engine from GitHub
releases with no Aether toolchain. The pure logic (asset naming, cache path,
platform mapping, the version pin) needs no network. One live download test is
gated on ``SELENIUM_FETCH_LIVE=1`` so the default suite stays offline and
deterministic.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile

import pytest

from selenium import engine_fetcher as F
from selenium import webdriver
from selenium import _native


def test_engine_version_is_a_release_tag():
    assert re.fullmatch(r"v\d+\.\d+\.\d+", F.ENGINE_VERSION), "vX.Y.Z gh-release tag"
    assert F.ENGINE_VERSION == webdriver.ENGINE_VERSION, "re-exported on selenium.webdriver"


def test_asset_name_matches_the_release_artifact_scheme():
    # libselenium_core-<tag>-<os>-<arch>.<ext> — exactly what release/build.sh emits.
    assert re.fullmatch(
        r"libselenium_core-v\d+\.\d+\.\d+-(linux|macos|windows)-(x86_64|arm64)\.(so|dylib|dll)",
        F.asset_name(),
    )


def test_cached_path_is_under_the_cache_dir_keyed_by_tag():
    path = F.cached_path()
    assert path.startswith(F.cache_dir()), "cached under the cache dir"
    assert F.ENGINE_VERSION in path, "keyed by the engine tag (survives pip upgrades)"
    assert os.path.basename(path) == F.library_filename(), "bare library filename the loader looks for"


def test_platform_mapping_is_total_for_this_host():
    # os_tag/arch_tag/ext must not raise on the host running the suite.
    assert F.os_tag() in ("linux", "macos", "windows")
    assert F.arch_tag() in ("x86_64", "arm64")
    assert F.ext() in ("so", "dylib", "dll")


def test_loader_looks_in_the_fetch_cache():
    # _native's candidate list must include exactly where the fetcher caches, so
    # a fetched engine loads with no further config.
    candidates = list(_native._candidate_paths())
    assert F.cached_path() in candidates


def test_cache_dir_honors_xdg(monkeypatch):
    monkeypatch.setenv("XDG_CACHE_HOME", "/somewhere/cache")
    assert F.cache_dir() == os.path.join("/somewhere/cache", "selaenium")


@pytest.mark.skipif(
    os.environ.get("SELENIUM_FETCH_LIVE") != "1",
    reason="set SELENIUM_FETCH_LIVE=1 to hit the network",
)
def test_live_fetch_downloads_and_verifies(monkeypatch):
    with tempfile.TemporaryDirectory() as tmp:
        monkeypatch.setenv("XDG_CACHE_HOME", tmp)
        path = webdriver.fetch_engine(force=True)
        assert os.path.isfile(path), "engine downloaded to the cache"
        assert os.path.getsize(path) > 0, "non-empty"
        want = F._expected_sha()
        if want:
            with open(path, "rb") as fh:
                got = hashlib.sha256(fh.read()).hexdigest()
            assert got == want, "matches the published .sha256"
