// Engine-path resolution for the shared pure-Aether engine (libselenium_core).
//
// The Go binding links the engine at BUILD time via the `#cgo LDFLAGS:` line in
// selenium.go, which searches two fixed, ${SRCDIR}-relative dirs: the module's
// own bundled native/ and the monorepo ../selenium_core/native sibling. cgo
// LDFLAGS directives can only expand ${SRCDIR} — NOT $XDG_CACHE_HOME or $HOME —
// so the shared fetch cache that scripts/fetch-engine.sh populates cannot be
// named in a static directive. This file gives a dev who only ran the fetch
// script (no Aether toolchain, no monorepo build) two supported ways in:
//
//  1. point the standard escape hatch at the fetched copy:
//     SELENIUM_CORE_LIB=$(scripts/fetch-engine.sh --path)
//     (honored by every binding; the go build/rpath picks up its parent dir via
//     CgoLdflags below), or
//  2. drop the fetched .so into the bundled slot go/native/ (symlink or copy),
//     which the static `-L${SRCDIR}/native` directive already links against.
//
// The resolution ORDER here mirrors rust/build.rs's resolve_dir():
//
//	SELENIUM_CORE_LIB -> bundled native/ -> the fetch cache -> monorepo sibling.
//
// It is used for RUNTIME dlopen/rpath fallback and by tests; the compile-time
// link path is still the cgo directive in selenium.go (plus any CGO_LDFLAGS the
// dev exports, e.g. from CgoLdflags).
package selenium

import (
	"os"
	"path/filepath"
	"runtime"
)

// EngineVersion is the engine gh-release tag whose fetch-cache this binding
// searches. It matches scripts/fetch-engine.sh's default TAG, rust/build.rs's
// ENGINE_VERSION, and the runtime bindings' ENGINE_VERSION.
const EngineVersion = "v0.8.0"

// libFilename is the bare filename the loader/linker looks for on this OS
// (the cache dir already keys by tag, so no tag/platform in the name).
func libFilename() string {
	switch runtime.GOOS {
	case "windows":
		return "selenium_core.dll"
	case "darwin":
		return "libselenium_core.dylib"
	default:
		return "libselenium_core.so"
	}
}

// CacheDir returns $XDG_CACHE_HOME/selaenium/<EngineVersion> (or the OS default
// base: ~/Library/Caches on macOS, %LOCALAPPDATA% on Windows, ~/.cache
// elsewhere) — the per-user, per-tag dir scripts/fetch-engine.sh and every
// runtime binding share. The path is returned whether or not it exists.
func CacheDir() string {
	return filepath.Join(cacheBase(), "selaenium", EngineVersion)
}

// cacheBase is the platform cache root, honoring XDG_CACHE_HOME first (matching
// fetch-engine.sh and the python/ruby fetchers).
func cacheBase() string {
	if xdg := os.Getenv("XDG_CACHE_HOME"); xdg != "" {
		return xdg
	}
	switch runtime.GOOS {
	case "windows":
		if la := os.Getenv("LOCALAPPDATA"); la != "" {
			return la
		}
		return filepath.Join(homeDir(), "AppData", "Local")
	case "darwin":
		return filepath.Join(homeDir(), "Library", "Caches")
	default:
		return filepath.Join(homeDir(), ".cache")
	}
}

func homeDir() string {
	if h, err := os.UserHomeDir(); err == nil && h != "" {
		return h
	}
	return os.Getenv("HOME")
}

// CachedEnginePath is the full path the fetched engine would occupy:
// CacheDir()/libselenium_core.<ext>. Equal to `scripts/fetch-engine.sh --path`.
func CachedEnginePath() string {
	return filepath.Join(CacheDir(), libFilename())
}

// EngineDir resolves the directory holding the engine .so, in the same order as
// rust/build.rs's resolve_dir(): SELENIUM_CORE_LIB's parent -> the module's
// bundled native/ -> the shared fetch cache -> the monorepo ../selenium_core/
// native sibling. It returns ("", false) if no .so is found in any of them — a
// caller can then surface a clear "run scripts/fetch-engine.sh" message.
func EngineDir() (string, bool) {
	if p := os.Getenv("SELENIUM_CORE_LIB"); p != "" {
		if fileExists(p) {
			return filepath.Dir(p), true
		}
	}
	for _, dir := range []string{bundledDir(), CacheDir(), monorepoDir()} {
		if dir == "" {
			continue
		}
		if fileExists(filepath.Join(dir, libFilename())) {
			return dir, true
		}
	}
	return "", false
}

// EnginePath is EngineDir joined with the platform library filename — the .so a
// caller would dlopen at run time — or ("", false) if unresolved. When
// SELENIUM_CORE_LIB names the file directly, that exact path is returned.
func EnginePath() (string, bool) {
	if p := os.Getenv("SELENIUM_CORE_LIB"); p != "" && fileExists(p) {
		return p, true
	}
	dir, ok := EngineDir()
	if !ok {
		return "", false
	}
	return filepath.Join(dir, libFilename()), true
}

// CgoLdflags returns the value a fetch-only dev can export as CGO_LDFLAGS so
// `go build`/`go test` link and rpath the engine from wherever EngineDir found
// it (the fetch cache, typically). cgo APPENDS $CGO_LDFLAGS to the per-package
// `#cgo LDFLAGS` directive, so this augments — never replaces — selenium.go's
// static search dirs. Returns "" when no engine is resolvable (the static
// directives then stand alone). Example:
//
//	export CGO_LDFLAGS="$(go run ./cmd/enginepath)"   # if you wrap it in a tiny main
//	# or, most directly, the one-liner in go/AGENTS.md using fetch-engine.sh --path.
func CgoLdflags() string {
	dir, ok := EngineDir()
	if !ok {
		return ""
	}
	return "-L" + dir + " -Wl,-rpath," + dir
}

func fileExists(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && !fi.IsDir()
}

func bundledDir() string {
	if dir := sourceDir(); dir != "" {
		return filepath.Join(dir, "native")
	}
	return ""
}

func monorepoDir() string {
	if dir := sourceDir(); dir != "" {
		return filepath.Join(dir, "..", "selenium_core", "native")
	}
	return ""
}

// sourceDir is the directory of THIS source file, used to locate the bundled
// native/ and the monorepo sibling relative to the checked-out module — the
// runtime analogue of the ${SRCDIR} the cgo directive uses at build time.
func sourceDir() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}
	return filepath.Dir(file)
}
