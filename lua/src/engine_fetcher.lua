-- engine_fetcher — fetch the prebuilt pure-Aether engine (libselenium_core) from
-- the project's GitHub releases and cache it, so a Lua dev needs no Aether
-- toolchain and no bundled .so. Mirrors the Ruby binding's EngineFetcher.
--
--   lua bin/fetch_engine.lua        -- or: require("selenium").fetch_engine()
--
-- downloads the right library for this OS+arch, verifies its published .sha256,
-- and drops it in the per-user cache the C extension's loader already searches.
-- Explicit, one-time, opt-in: nothing downloads at require time.
--
-- Lua's stdlib has no HTTP or SHA-256, so this orchestrates the ubiquitous
-- system tools (curl or wget for the download following GitHub's CDN redirect,
-- sha256sum/shasum for verification) rather than pulling in luasocket/luacrypto.
-- Keeps the binding dependency-free, consistent with the C-extension approach.

local F = {}

-- The engine gh-release TAG this binding downloads from (distinct from the
-- binding's own version). Bump when re-glued to a newer engine.
F.ENGINE_VERSION = "v0.9.0"
F.REPO = "aether-lang-dev/selaenium"
F.RELEASE_BASE = "https://github.com/" .. F.REPO .. "/releases/download"

-- ---- platform mapping (matches release/build.sh's artifact names) ----

-- uname-based detection (no external Lua deps). Cached after first probe.
local _uname_s, _uname_m
local function uname(flag)
  local p = io.popen("uname " .. flag .. " 2>/dev/null")
  if not p then return "" end
  local out = (p:read("*a") or ""):gsub("%s+$", "")
  p:close()
  return out
end

function F.os_tag()
  if not _uname_s then _uname_s = uname("-s") end
  local s = _uname_s:lower()
  if s:find("linux") then return "linux"
  elseif s:find("darwin") then return "macos"
  elseif s:find("mingw") or s:find("msys") or s:find("cygwin") or s:find("windows") then return "windows"
  else error("selenium: unsupported OS for a prebuilt engine: " .. _uname_s) end
end

function F.arch_tag()
  if not _uname_m then _uname_m = uname("-m") end
  local m = _uname_m:lower()
  if m:find("x86_64") or m:find("amd64") then return "x86_64"
  elseif m:find("arm64") or m:find("aarch64") then return "arm64"
  else error("selenium: unsupported CPU for a prebuilt engine: " .. _uname_m) end
end

function F.ext()
  local os_ = F.os_tag()
  if os_ == "macos" then return "dylib"
  elseif os_ == "windows" then return "dll"
  else return "so" end
end

-- The gh-release asset for this platform, e.g. libselenium_core-v0.8.0-linux-x86_64.so
function F.asset_name(tag)
  tag = tag or F.ENGINE_VERSION
  return string.format("libselenium_core-%s-%s-%s.%s", tag, F.os_tag(), F.arch_tag(), F.ext())
end

-- The bare local filename the loader looks for (cache dir already keys by tag).
function F.library_filename()
  local os_ = F.os_tag()
  if os_ == "windows" then return "selenium_core.dll"
  elseif os_ == "macos" then return "libselenium_core.dylib"
  else return "libselenium_core.so" end
end

-- $XDG_CACHE_HOME/selaenium (or the OS default), kept out of the package so it
-- survives reinstalls: ~/.cache on Linux, ~/Library/Caches on macOS,
-- %LOCALAPPDATA% on Windows.
function F.cache_dir()
  local xdg = os.getenv("XDG_CACHE_HOME")
  local base
  if xdg and xdg ~= "" then
    base = xdg
  elseif F.os_tag() == "windows" then
    base = os.getenv("LOCALAPPDATA") or (os.getenv("USERPROFILE") .. "/AppData/Local")
  elseif F.os_tag() == "macos" then
    base = (os.getenv("HOME") or "") .. "/Library/Caches"
  else
    base = (os.getenv("HOME") or "") .. "/.cache"
  end
  return base .. "/selaenium"
end

-- Absolute path the fetched engine is cached at (whether or not it exists yet) —
-- exactly what the C extension's candidate list adds, so a fetched engine loads
-- with no further config.
function F.cached_path(tag)
  tag = tag or F.ENGINE_VERSION
  return F.cache_dir() .. "/" .. tag .. "/" .. F.library_filename()
end

-- ---- helpers (shell out to ubiquitous tools) ----

local function has(cmd)
  return os.execute("command -v " .. cmd .. " >/dev/null 2>&1")
end

local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close() return true end
  return false
end

local function sha256_of(path)
  local tool
  if has("sha256sum") then tool = "sha256sum '" .. path .. "'"
  elseif has("shasum") then tool = "shasum -a 256 '" .. path .. "'"
  else return nil end
  local p = io.popen(tool .. " 2>/dev/null")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  return out:match("^(%x+)")
end

-- Download url -> dest via curl (preferred) or wget, following redirects.
local function download(url, dest)
  local cmd
  if has("curl") then
    cmd = string.format("curl -fsSL -o '%s' '%s'", dest, url)
  elseif has("wget") then
    cmd = string.format("wget -q -O '%s' '%s'", dest, url)
  else
    error("selenium: need curl or wget to fetch the engine (neither found)")
  end
  return os.execute(cmd)
end

-- Fetch the published <asset>.sha256 sidecar and return the hex (nil if absent).
local function expected_sha(tag)
  local tmp = os.tmpname()
  local url = string.format("%s/%s/%s.sha256", F.RELEASE_BASE, tag, F.asset_name(tag))
  if not download(url, tmp) then os.remove(tmp) return nil end
  local fh = io.open(tmp, "r")
  local hex
  if fh then hex = (fh:read("*a") or ""):match("^(%x+)") fh:close() end
  os.remove(tmp)
  return hex
end

-- fetch{tag=, force=} -> cached path. Idempotent: a present, checksum-matching
-- copy is returned with no network call. Verifies the .sha256 when published.
function F.fetch(opts)
  opts = opts or {}
  local tag = opts.tag or F.ENGINE_VERSION
  local dest = F.cached_path(tag)
  local want = nil

  if not opts.force and file_exists(dest) then
    want = expected_sha(tag)
    if not want or sha256_of(dest) == want then return dest end
  end

  -- mkdir -p the cache subdir
  local dir = dest:match("^(.*)/[^/]+$")
  os.execute("mkdir -p '" .. dir .. "'")

  local url = string.format("%s/%s/%s", F.RELEASE_BASE, tag, F.asset_name(tag))
  local tmp = dest .. "." .. tostring(os.time()) .. ".part"
  if not download(url, tmp) then
    os.remove(tmp)
    error("selenium: failed to download " .. url)
  end

  want = want or expected_sha(tag)
  if want then
    local got = sha256_of(tmp)
    if got and got ~= want then
      os.remove(tmp)
      error(string.format("selenium: checksum mismatch for %s: expected %s, got %s",
        F.asset_name(tag), want, got))
    end
  end

  os.rename(tmp, dest)   -- atomic within the same dir
  return dest
end

return F
