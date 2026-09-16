"""``python -m selenium.fetch_engine`` — the one command a Python dev runs after
``pip install selenium`` to pull the prebuilt pure-Aether engine
(``libselenium_core``) for their platform from GitHub releases. No Aether
toolchain, no compiler.

    python -m selenium.fetch_engine                 # fetch the pinned engine
    python -m selenium.fetch_engine --tag v0.8.0    # pin a specific engine release
    python -m selenium.fetch_engine --force         # re-download even if cached
    python -m selenium.fetch_engine --path          # just print the cache path

Mirrors Ruby's ``rake selenium:fetch_engine`` / ``rake selenium:engine_path``.
"""

from __future__ import annotations

import argparse
import sys

from . import engine_fetcher


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m selenium.fetch_engine",
        description=(
            "Download + cache the prebuilt engine (libselenium_core) for this "
            "platform from GitHub releases. `import selenium` then loads it "
            "automatically."
        ),
    )
    parser.add_argument(
        "--tag",
        default=engine_fetcher.ENGINE_VERSION,
        help=f"engine gh-release tag to fetch (default: {engine_fetcher.ENGINE_VERSION})",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-download even if a checksum-matching copy is already cached",
    )
    parser.add_argument(
        "--path",
        action="store_true",
        help="print where the engine is (or would be) cached and exit",
    )
    args = parser.parse_args(argv)

    if args.path:
        print(engine_fetcher.cached_path(args.tag))
        return 0

    asset = engine_fetcher.asset_name(args.tag)
    print(f"selenium: fetching engine {asset} ({args.tag}) ...", file=sys.stderr)
    try:
        path = engine_fetcher.fetch(tag=args.tag, force=args.force)
    except engine_fetcher.FetchError as exc:
        print(f"selenium: fetch failed: {exc}", file=sys.stderr)
        return 1
    print(f"selenium: engine ready at {path}", file=sys.stderr)
    print("selenium: `import selenium` will now load it automatically.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
