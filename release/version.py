#!/usr/bin/env python3
"""Set or check the engine release pin across independently shipped bindings."""

import argparse
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent
TAG = r"v\d+\.\d+\.\d+"
# Each expression captures only the version, preserving formatting and comments.
PINS = {
    "SELENIUM_CORE_VERSION": rf"^({TAG})\s*$",
    "aether.toml": r'^version = "(\d+\.\d+\.\d+)"$',
    "crystal/shard.yml": r'^version: (\d+\.\d+\.\d+)$',
    "python/selenium/engine_fetcher.py": rf'ENGINE_VERSION = "({TAG})"',
    "ruby/lib/selenium/engine_fetcher.rb": rf"ENGINE_VERSION = '({TAG})'",
    "dart/lib/src/engine_fetcher.dart": rf"engineVersion = '({TAG})'",
    "dart/test/engine_fetcher_test.dart": rf"expect\(EngineFetcher.engineVersion, '({TAG})'\)",
    "java/src/main/java/org/openqa/selenium/Native.java": rf'ENGINE_VERSION = "({TAG})"',
    "javascript/lib/native.js": rf"ENGINE_VERSION = '({TAG})'",
    "dotnet/SeleniumCore/NativeLoader.cs": rf'EngineVersion = "({TAG})"',
    "go/enginepath.go": rf'SeleniumCoreVersion = "({TAG})"',
    "swift/Package.swift": rf'seleniumCoreVersion = "({TAG})"',
    "swift/Tests/SeleniumTests/VersionTests.swift": rf'expectedSeleniumCoreVersion = "({TAG})"',
    "zig/build.zig": rf'SELENIUM_CORE_VERSION = "({TAG})"',
    "lua/src/selenium_core.c": rf'#define ENGINE_VERSION "({TAG})"',
    "lua/src/engine_fetcher.lua": rf'F.ENGINE_VERSION = "({TAG})"',
    "php/src/EngineFetcher.php": rf"ENGINE_VERSION = '({TAG})'",
    "julia/src/Selenium.jl": rf'ENGINE_VERSION = "({TAG})"',
    "crystal/src/selenium.cr": rf'SELENIUM_CORE_VERSION = "({TAG})"',
    "crystal/bin/crystal-build": rf'ENGINE_VERSION="\$\{{ENGINE_VERSION:-({TAG})\}}"',
    "haskell/bin/cabal-build": rf'ENGINE_VERSION="\$\{{ENGINE_VERSION:-({TAG})\}}"',
    "c/.build.ae": rf'return "({TAG})"',
    "cpp/.tests.ae": rf'return "({TAG})"',
}
# Documentation copies of the old pin, including the Swift test's explanation.
REFERENCES = (
    "README.md", "go/README.md", "go/AGENTS.md", "zig/README.md", "haskell/selenium.cabal",
    "swift/Tests/SeleniumTests/VersionTests.swift",
)


def version_files(root, tag):
    """Read and validate every pin before any file is changed."""
    files = {}
    mismatches = []
    for name, pattern in PINS.items():
        content = (root / name).read_text()
        matches = list(re.finditer(pattern, content, re.MULTILINE))
        expected_count = 2 if name in ("c/.build.ae", "cpp/.tests.ae") else 1
        if len(matches) != expected_count:
            raise ValueError(f"{name}: expected {expected_count} version pin(s), found {len(matches)}")
        want = tag.removeprefix("v") if name in ("aether.toml", "crystal/shard.yml") else tag
        for match in reversed(matches):
            if match[1] != want:
                mismatches.append(f"{name}: {match[1]} != {want}")
            start, end = match.span(1)
            content = content[:start] + want + content[end:]
        files[name] = content
    return files, mismatches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--set", dest="set_tag", metavar="TAG", help="prepare all pins for a new release")
    mode.add_argument("--check", dest="check_tag", nargs="?", const="", metavar="TAG", help="check pins against TAG (default: SELENIUM_CORE_VERSION)")
    args = parser.parse_args()
    try:
        tag = args.set_tag or args.check_tag or (ROOT / "SELENIUM_CORE_VERSION").read_text().strip()
        if not re.fullmatch(TAG, tag):
            raise ValueError(f"expected a release tag vX.Y.Z, got {tag!r}")
        files, mismatches = version_files(ROOT, tag)
        if args.set_tag:
            old = (ROOT / "SELENIUM_CORE_VERSION").read_text().strip()
            for name in REFERENCES:
                content = files.get(name, (ROOT / name).read_text())
                files[name] = content.replace(old, tag)
            for name, content in files.items():
                (ROOT / name).write_text(content)
            print(f"Prepared engine pins for {tag}; commit before tagging, then verify the published downloads.")
        elif mismatches:
            raise ValueError("engine version pins disagree:\n" + "\n".join(mismatches))
        else:
            print(f"All engine version pins match {tag}.")
    except (OSError, ValueError) as error:
        parser.exit(1, f"version: {error}\n")


if __name__ == "__main__":
    main()
