#!/usr/bin/env python3
"""Check the complete release asset set, checksums, and the loadable Linux ABI."""

import argparse
import ctypes
import hashlib
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = (
    ("linux", "x86_64", "so"), ("linux", "arm64", "so"),
    ("linux", "x86_64-musl", "so"), ("linux", "arm64-musl", "so"),
    ("macos", "x86_64", "dylib"), ("macos", "arm64", "dylib"),
    ("windows", "x86_64", "dll"), ("windows", "arm64", "dll"),
    ("freebsd", "x86_64", "so"),
)


def check_artifacts(tag, dist):
    manifest = {}
    for line in (dist / "SHA256SUMS.txt").read_text().splitlines():
        digest, name = line.split()
        manifest[name.removeprefix("./")] = digest
    for os_name, arch, extension in PLATFORMS:
        name = f"libselenium_core-{tag}-{os_name}-{arch}.{extension}"
        names = (name, name + ".lib") if os_name == "windows" else (name,)
        for filename in names:
            artifact = dist / filename
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            if artifact.stat().st_size == 0:
                raise ValueError(f"empty artifact: {filename}")
            sidecar = (dist / (filename + ".sha256")).read_text().split()
            if sidecar != [digest, filename] or manifest.get(filename) != digest:
                raise ValueError(f"checksum mismatch: {filename}")
        if os_name == "linux":
            dynamic = subprocess.run(["readelf", "-d", str(dist / name)], check=True, capture_output=True, text=True).stdout
            needed = re.findall(r"\(NEEDED\).*?\[([^\]]+)\]", dynamic)
            expected = "libc.so" if arch.endswith("-musl") else "libc.so.6"
            other = "libc.so.6" if arch.endswith("-musl") else "libc.so"
            if expected not in needed or other in needed:
                raise ValueError(f"wrong Linux libc for {name}: {needed}")
    lib = ctypes.CDLL(str((dist / f"libselenium_core-{tag}-linux-x86_64.so").resolve()))
    exports = re.findall(r"^(sel_embed_\w+)\(", (ROOT / "selenium_core/embed.ae").read_text(), re.MULTILINE)
    if not exports:
        raise ValueError("no engine ABI declarations found")
    for symbol in exports:
        getattr(lib, "aether_" + symbol)
    print(f"Verified all nine engine libraries, Windows import libraries, checksums, and {len(exports)} Linux ABI exports.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--dist", type=Path, default=ROOT / "release/dist")
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
        parser.error("expected a release tag vX.Y.Z")
    try:
        check_artifacts(args.tag, args.dist)
    except (OSError, ValueError, AttributeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"artifacts: {error}\n")


if __name__ == "__main__":
    main()
