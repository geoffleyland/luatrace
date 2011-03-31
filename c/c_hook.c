#include <time.h>
#include "lauxlib.h"

/*============================================================================*/

static clock_t time_out, elapsed;
static int hook_index = -1;


void hook(lua_State *L, lua_Debug *ar)
{
  clock_t time_in = clock();
  elapsed += time_in - time_out;
  
  int event = ar->event;
  if (event == LUA_HOOKLINE ||
      event == LUA_HOOKCALL ||
      event == LUA_HOOKRET)
  {
    lua_rawgeti(L, LUA_REGISTRYINDEX, hook_index);
    if (event == LUA_HOOKLINE) lua_pushstring(L, "line");
    if (event == LUA_HOOKCALL) lua_pushstring(L, "call");
    if (event == LUA_HOOKRET)  lua_pushstring(L, "return");
    if (event == LUA_HOOKLINE) lua_pushnumber(L, ar->currentline);
    else lua_pushnil(L);
    lua_pushinteger(L, elapsed);
    lua_call(L, 3, 0);
    
    elapsed = 0;
  }
  time_out = clock();
}


static int set_hook(lua_State *L)
{
  if (lua_isnoneornil(L, 1))
  {
    if (hook_index >= 0)
    {
      luaL_unref(L, LUA_REGISTRYINDEX, hook_index);
      hook_index = -1;
    }
    lua_sethook(L, 0, 0, 0);
  }
  else
  {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    hook_index = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_sethook(L, hook, LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE, 0);
    elapsed = 0;
    time_out = clock();
  }
}

/*============================================================================*/


static luaL_Reg hook_functions[] =
{
  {"set_hook",  set_hook},
  {NULL, NULL}
};


LUALIB_API int luaopen_luatrace_c_hook(lua_State *L)
{
  // Register the module functions
  luaL_register(L, "c_hook", hook_functions);
  return 1;
}


/*============================================================================*/

