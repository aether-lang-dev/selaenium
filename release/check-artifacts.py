#!/usr/bin/env python3
"""Check the complete release asset set, checksums, and the loadable Linux ABI."""

import argparse
import ctypes
import hashlib
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent


def check_artifacts(tag, dist):
    manifest = {}
    for line in (dist / "SHA256SUMS.txt").read_text().splitlines():
        digest, name = line.split()
        manifest[name.removeprefix("./")] = digest
    for os_name, extension in (("linux", "so"), ("macos", "dylib"), ("windows", "dll")):
        for arch in ("x86_64", "arm64"):
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
    lib = ctypes.CDLL(str((dist / f"libselenium_core-{tag}-linux-x86_64.so").resolve()))
    exports = re.findall(r"^(sel_embed_\w+)\(", (ROOT / "selenium_core/embed.ae").read_text(), re.MULTILINE)
    if not exports:
        raise ValueError("no engine ABI declarations found")
    for symbol in exports:
        getattr(lib, "aether_" + symbol)
    print(f"Verified all six engine libraries, Windows import libraries, checksums, and {len(exports)} Linux ABI exports.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--dist", type=Path, default=ROOT / "release/dist")
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
        parser.error("expected a release tag vX.Y.Z")
    try:
        check_artifacts(args.tag, args.dist)
    except (OSError, ValueError, AttributeError) as error:
        parser.exit(1, f"artifacts: {error}\n")


if __name__ == "__main__":
    main()
