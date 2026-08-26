#!/usr/bin/env bash
# Groovy binding: compile the Java FFM binding classes AND the Groovy wrapper,
# then run the Groovy test against them. The Groovy layer is pure Java-interop
# over the one JVM binding — no second FFI.
#
# Toolchain reality: the Java binding is Panama FFM (JDK 22+). Debian's Groovy
# 2.4 runs on JVM 17 and can't read JDK-22+ bytecode, so we need a modern Groovy
# (>= 4) on a JDK >= 22. Discovery order:
#   1. $GROOVY_HOME/bin/groovy(c)
#   2. ~/.sdkman/candidates/groovy/current/bin/groovy(c)
#   3. a `groovy` on PATH THAT IS >= 4
# SKIPS LOUDLY (exit 0) when none is found.
# Args: <engine .so path> <java-src-dir> <groovy-dir>
set -u
ENGINE="${1:?}"; JAVA_SRC="${2:?}"; GDIR="${3:?}"

find_groovy_dir() {
  if [ -n "${GROOVY_HOME:-}" ] && [ -x "$GROOVY_HOME/bin/groovy" ]; then echo "$GROOVY_HOME/bin"; return 0; fi
  local sdk="$HOME/.sdkman/candidates/groovy/current/bin"
  if [ -x "$sdk/groovy" ]; then echo "$sdk"; return 0; fi
  if command -v groovy >/dev/null 2>&1; then
    local v; v="$(groovy --version 2>&1 | grep -oE 'Groovy Version: [0-9]+' | grep -oE '[0-9]+' | head -1)"
    if [ -n "$v" ] && [ "$v" -ge 4 ]; then dirname "$(command -v groovy)"; return 0; fi
  fi
  return 1
}

GBIN="$(find_groovy_dir)" || {
  echo "groovy tests: SKIPPED — no Groovy >= 4 on a JDK >= 22 found (Debian's 2.4/JVM17 can't read the FFM binding; set GROOVY_HOME or install via sdkman)"
  exit 0
}
GROOVY="$GBIN/groovy"
GROOVYC="$GBIN/groovyc"

JOUT="$GDIR/jout"
GOUT="$GDIR/gout"
rm -rf "$JOUT" "$GOUT"; mkdir -p "$JOUT" "$GOUT"

# Compile the Java FFM binding classes.
javac -d "$JOUT" "$JAVA_SRC"/*.java || { echo "groovy tests: javac (Java binding) FAILED"; exit 1; }
# Compile the Groovy idiomatic wrapper against them (into GOUT).
"$GROOVYC" -cp "$JOUT" -d "$GOUT" "$GDIR/src/SeleniumCore.groovy" \
  || { echo "groovy tests: groovyc (wrapper) FAILED"; exit 1; }

# Run the test script with the Java classes + compiled Groovy wrapper on the cp.
SELENIUM_CORE_LIB="$ENGINE" \
  JAVA_OPTS="--enable-native-access=ALL-UNNAMED" \
  "$GROOVY" -cp "$JOUT:$GOUT" "$GDIR/test/live_test.groovy"
