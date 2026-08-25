/* lua/host/lua54.c — a minimal Lua 5.4 interpreter, built only when the
 * platform ships liblua5.4 without the matching `lua5.4` binary.
 *
 * Debian 12 is exactly that case: liblua5.4-dev provides the headers and the
 * shared library, but the packaged interpreter is 5.3, which cannot load a
 * 5.4 extension (`undefined symbol: lua_newuserdatauv`). Rather than skip the
 * Lua binding's tests on such a box, build a host that IS 5.4.
 *
 * This is test scaffolding, not part of the binding: `htmlsanitizer_native.so`
 * loads into any real Lua 5.4 host (the distro's `lua5.4`, a Redis/nginx
 * embed, LÖVE, whatever). build.sh skips this entirely when a `lua5.4` binary
 * is already available.
 *
 *   cc -O2 -I/usr/include/lua5.4 host/lua54.c -o lua54 -llua5.4 -lm -ldl
 *   ./lua54 test/conformance.lua
 */
#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s script.lua [args...]\n", argv[0]);
        return 2;
    }

    lua_State* L = luaL_newstate();
    if (!L) { fprintf(stderr, "lua54: out of memory\n"); return 1; }
    luaL_openlibs(L);

    /* The conventional `arg` table: arg[0] is the script, arg[1..] its args. */
    lua_newtable(L);
    lua_pushstring(L, argv[1]);
    lua_rawseti(L, -2, 0);
    for (int i = 2; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i - 1);
    }
    lua_setglobal(L, "arg");

    if (luaL_dofile(L, argv[1]) != LUA_OK) {
        const char* msg = lua_tostring(L, -1);
        fprintf(stderr, "%s\n", msg ? msg : "(non-string error)");
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
