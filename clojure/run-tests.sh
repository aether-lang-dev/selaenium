#!/usr/bin/env bash
# Clojure binding: compile the Java FFM binding classes, then run the Clojure
# test against them. Clojure is JVM-family — it consumes the ONE Java jar over
# Clojure/Java interop, no second FFI, no second .so. Args:
#   $1 = engine .so path (SELENIUM_CORE_LIB)
#   $2 = the Java binding src dir (java/src/org/seleniumhq/aether)
#   $3 = this clojure/ dir
#
# Uses the modern Clojure CLI (deps.edn/tools.deps, v1.12+): classpath comes
# from -Sdeps ':paths', NOT the removed '-cp' flag (-cp is misparsed as a file,
# and -Scp would replace clojure's own jars). SKIPS LOUDLY (exit 0) if clojure
# is absent. The FFM binding needs --enable-native-access, threaded in via
# JAVA_TOOL_OPTIONS (the packaged clojure launcher is plain clojure.main, no -J).
set -u
ENGINE="${1:?need engine .so}"
JSRC="${2:?need java src dir}"
CDIR="${3:?need clojure dir}"

if ! command -v clojure >/dev/null 2>&1; then
  echo "clojure tests: SKIPPED — clojure not on PATH"
  exit 0
fi

JOUT="$CDIR/jout"
rm -rf "$JOUT" && mkdir -p "$JOUT"
if ! javac -d "$JOUT" "$JSRC"/*.java; then
  echo "clojure tests: javac (Java binding) FAILED"
  exit 1
fi

# -Sdeps with :paths lets the CLI compute the FULL classpath (clojure + ours).
# Single-quote the EDN so its double-quotes survive the shell verbatim.
cd "$CDIR" || exit 1
SELENIUM_CORE_LIB="$ENGINE" \
JAVA_TOOL_OPTIONS="--enable-native-access=ALL-UNNAMED" \
  clojure -Sdeps '{:paths ["jout" "src" "test"]}' -M -m live-test
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "clojure tests: FAILED"
  exit 1
fi
echo "clojure tests: PASSED (ffi + live+surface)"
exit 0
