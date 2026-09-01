# Package manifest for the Nim binding.
#
# This package LINKS the native engine (see src/selenium.nim's {.passL.}), so
# libselenium_core.so must be present at COMPILE time, not just at run time.
# nim/.tests.ae stages it into nim/native/; an in-tree checkout also has
# core/native/libselenium_core.so, and both dirs are on the link path and baked
# in as rpath.
#
# No `requires` beyond nim itself: a binding that marshals to a C ABI + std/json
# needs no third-party code, keeping `nimble install` offline.

version       = "0.1.0"
author        = "Paul Hammant"
description   = "Selenium WebDriver for Nim — a thin binding over the shared pure-Aether WebDriver core"
license       = "Apache-2.0"
srcDir        = "src"

requires "nim >= 1.6.0"

# `nimble test` compiles + runs the suite. Equally runnable without nimble,
# which is how .tests.ae drives it (nim c -r ...).
task test, "Run the FFI + live-surface suite":
  exec "nim c -r --hints:off --path:src tests/tffi.nim"
  exec "nim c -r --hints:off --threads:on --path:src tests/tlive.nim"
