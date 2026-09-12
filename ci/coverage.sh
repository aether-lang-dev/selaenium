#!/usr/bin/env bash
# ci/coverage.sh — what did the presubmit ACTUALLY test?
#
# aeb's per-node `prereq(...)` is meant to skip a binding whose toolchain is
# absent, and a skip is green: the binding is fine, the box is under-provisioned.
# The problem is that a skip is INVISIBLE — a node whose toolchain is missing can
# report "tests PASSED" with no marker distinguishing it from a node that really
# ran. Two observed on a dev box:
#
#   tests_d.log:     sh: line 1: dmd: command not found
#                    tests:d: tests PASSED (2 file(s))
#   tests_swift.log: tests:swift: FAILED — build FAILED
#                    tests:swift: tests PASSED
#
# So "presubmit green" on its own does not mean "28 bindings tested". This script
# says which ones actually could have been, by checking each node's declared
# prereq itself — independently of what aeb reported.
#
# It RUNS each tool rather than just looking for it on PATH: `swift` above is on
# PATH and still cannot execute (missing libncurses), which `command -v` would
# happily call present.
#
# Usage:
#   ci/coverage.sh            # print the table, always exit 0
#   ci/coverage.sh --strict   # exit 1 if any binding could not be tested
#
# --strict is what CI should run: a box that cannot test every binding must not
# report the same green as one that can.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

# prereq token -> a command that must succeed for that toolchain to be usable.
probe() {
    case "$1" in
        aether)   ae --version ;;
        dmd)      dmd --version ;;
        dart)     dart --version ;;
        dotnet*)  dotnet --version ;;
        elixir)   elixir --version ;;
        erlang)   erl -eval 'halt().' -noshell ;;
        gcc)      gcc --version ;;
        ghc)      ghc --version ;;
        gleam)    gleam --version ;;
        go*)      go version ;;
        jdk*)     javac -version ;;
        lfe)      lfe --version ;;
        nim)      nim --version ;;
        node*)    node --version ;;
        php)      php --version ;;
        python*)  python3 --version ;;
        ruby*)    ruby --version ;;
        rust*)    cargo --version ;;
        swift)    swift --version ;;
        zig)      zig version ;;
        *)        return 2 ;;   # unknown token — report rather than assume
    esac
}

printf '%-40s %-12s %s\n' "NODE" "PREREQ" "STATUS"
printf '%s\n' "----------------------------------------------------------------------------"

tested=0; untested=0; unknown=0; ungated=0; missing=""
for node in $(find . -maxdepth 3 -name ".tests.ae" -not -path "./target/*" | sed 's|^\./||' | sort); do
    prereqs="$(grep -oE 'prereq\("[^"]+"\)' "$node" | sed 's/prereq("//;s/")//')"
    if [ -z "$prereqs" ]; then
        # No prereq() gate: a missing toolchain fails this node loudly rather
        # than passing quietly, so there is nothing to verify here.
        printf '%-40s %-12s %s\n' "$node" "-" "ungated (absence fails loudly)"
        ungated=$((ungated + 1))
        continue
    fi
    node_ok=1
    for p in $prereqs; do
        if probe "$p" >/dev/null 2>&1; then
            printf '%-40s %-12s %s\n' "$node" "$p" "tested"
        else
            rc=$?
            if [ "$rc" = "2" ]; then
                printf '%-40s %-12s %s\n' "$node" "$p" "UNKNOWN prereq — teach ci/coverage.sh about it"
                unknown=$((unknown + 1))
            else
                printf '%-40s %-12s %s\n' "$node" "$p" "NOT TESTED — toolchain absent or broken"
                missing="$missing $node($p)"
            fi
            node_ok=0
        fi
    done
    [ "$node_ok" = "1" ] && tested=$((tested + 1)) || untested=$((untested + 1))
done

printf '%s\n' "----------------------------------------------------------------------------"
printf '  gated + tested : %s\n' "$tested"
printf '  ungated        : %s (a missing toolchain would fail, not skip)\n' "$ungated"
printf '  NOT TESTED     : %s%s\n' "$untested" "${missing:+ —$missing}"
[ "$unknown" -gt 0 ] && printf '  unknown prereqs: %s\n' "$unknown"

if [ "$STRICT" = "1" ] && { [ "$untested" -gt 0 ] || [ "$unknown" -gt 0 ]; }; then
    echo
    echo "ci/coverage: FAILED (--strict) — this box cannot test every binding, so a"
    echo "             green presubmit here does not mean what it means in CI."
    exit 1
fi
exit 0
