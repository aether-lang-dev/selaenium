// Unit tests for the engine-path resolver — pure path logic, no browser and no
// engine .so needed (though cgo still links one to build the package).
package selenium

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestSeleniumCoreVersionPin(t *testing.T) {
	// The repo-root SELENIUM_CORE_VERSION file is the single source of truth for
	// the libselenium_core release tag. go:embed cannot reach a parent dir, so
	// this binding keeps a literal SeleniumCoreVersion — but this test reads the file
	// and fails if the literal drifts from it, so the two cannot silently diverge.
	b, err := os.ReadFile(filepath.Join("..", "SELENIUM_CORE_VERSION"))
	if err != nil {
		t.Fatalf("reading SELENIUM_CORE_VERSION: %v", err)
	}
	if want := strings.TrimSpace(string(b)); SeleniumCoreVersion != want {
		t.Fatalf("SeleniumCoreVersion = %q, but SELENIUM_CORE_VERSION says %q — update the constant", SeleniumCoreVersion, want)
	}
}

func TestCacheDirHonorsXDG(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", "/somewhere/cache")
	want := filepath.Join("/somewhere/cache", "selaenium", SeleniumCoreVersion)
	if got := CacheDir(); got != want {
		t.Fatalf("CacheDir() = %q, want %q", got, want)
	}
	// CachedEnginePath is exactly `fetch-engine.sh --path` for this platform.
	if got := CachedEnginePath(); got != filepath.Join(want, libFilename()) {
		t.Fatalf("CachedEnginePath() = %q", got)
	}
}

func TestCacheDirDefaultBase(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("default-base check is Linux-specific")
	}
	t.Setenv("XDG_CACHE_HOME", "")
	t.Setenv("HOME", "/home/tester")
	want := filepath.Join("/home/tester", ".cache", "selaenium", SeleniumCoreVersion)
	if got := CacheDir(); got != want {
		t.Fatalf("CacheDir() = %q, want %q", got, want)
	}
}

// SELENIUM_CORE_LIB pointing at a real file wins, and its PARENT dir is what
// EngineDir/CgoLdflags use (mirroring rust/build.rs).
func TestEngineDirEnvOverride(t *testing.T) {
	dir := t.TempDir()
	so := filepath.Join(dir, libFilename())
	if err := os.WriteFile(so, []byte("stub"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("SELENIUM_CORE_LIB", so)

	if got, ok := EngineDir(); !ok || got != dir {
		t.Fatalf("EngineDir() = (%q,%v), want (%q,true)", got, ok, dir)
	}
	if got, ok := EnginePath(); !ok || got != so {
		t.Fatalf("EnginePath() = (%q,%v), want (%q,true)", got, ok, so)
	}
	if got, want := CgoLdflags(), "-L"+dir+" -Wl,-rpath,"+dir; got != want {
		t.Fatalf("CgoLdflags() = %q, want %q", got, want)
	}
}

// A cache dir with the .so is resolved when SELENIUM_CORE_LIB is unset and no
// bundled/monorepo copy is reachable — the fetch-only dev path.
func TestEngineDirFindsCache(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	t.Setenv("SELENIUM_CORE_LIB", "")
	full := filepath.Join(cache, "selaenium", SeleniumCoreVersion)
	if err := os.MkdirAll(full, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(full, libFilename()), []byte("stub"), 0o644); err != nil {
		t.Fatal(err)
	}
	// The real module dir has a bundled native/ .so which would win over the
	// cache, so this asserts the cache is at least reachable, not that it is
	// chosen ahead of a genuine bundled copy.
	if got := CachedEnginePath(); got != filepath.Join(full, libFilename()) {
		t.Fatalf("CachedEnginePath() = %q", got)
	}
}
