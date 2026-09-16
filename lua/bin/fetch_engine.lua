#!/usr/bin/env lua
-- fetch_engine — the one command a Lua dev runs to get the prebuilt engine.
--
--   lua bin/fetch_engine.lua [--tag vX.Y.Z] [--force] [--path]
--
-- Downloads + caches the prebuilt libselenium_core for this platform from the
-- project's GitHub releases (no Aether toolchain needed); the C extension then
-- loads it from the cache automatically. Mirrors Ruby's `rake selenium:fetch_engine`.

-- Resolve the module beside this script (bin/ -> ../src) without needing it installed.
local here = (arg[0] or ""):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../src/?.lua;" .. package.path

local F = require("engine_fetcher")

local tag, force, path_only = F.ENGINE_VERSION, false, false
local i = 1
while arg[i] do
  local a = arg[i]
  if a == "--tag" then i = i + 1; tag = arg[i]
  elseif a:match("^%-%-tag=") then tag = a:sub(7)
  elseif a == "--force" then force = true
  elseif a == "--path" then path_only = true
  elseif a == "--help" or a == "-h" then
    io.write("usage: fetch_engine.lua [--tag vX.Y.Z] [--force] [--path]\n")
    os.exit(0)
  else
    io.stderr:write("fetch_engine: unknown argument: " .. a .. "\n"); os.exit(2)
  end
  i = i + 1
end

if path_only then
  print(F.cached_path(tag))
  os.exit(0)
end

io.stderr:write("selenium: fetching engine " .. F.asset_name(tag) .. " (" .. tag .. ") ...\n")
local ok, res = pcall(F.fetch, { tag = tag, force = force })
if not ok then
  io.stderr:write(tostring(res) .. "\n")
  os.exit(1)
end
io.stderr:write("selenium: engine ready at " .. res .. "\n")
io.stderr:write("selenium: require('selenium') will now load it automatically.\n")
