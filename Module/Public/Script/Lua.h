// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <mutex>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

namespace Kyber
{
#define KB_LUA_DECLARE_TABLE(type, name)                                                                                                   \
    type* Wrap##name(lua_State* L, type value);                                                                                            \
    type Get##name(lua_State* L, int index);                                                                                               \
    template<>                                                                                                                             \
    void LuaUtils::Push<type>(lua_State * L, type value);

#define KB_LUA_CREATE_TABLE(type, name)                                                                                                    \
    static type* Wrap##name(lua_State* L, type value)                                                                                      \
    {                                                                                                                                      \
        type* ptr = (type*)lua_newuserdata(L, sizeof(type*));                                                                              \
        *ptr = value;                                                                                                                      \
        luaL_getmetatable(L, #name);                                                                                             \
        lua_setmetatable(L, -2);                                                                                                           \
        return ptr;                                                                                                                        \
    }                                                                                                                                      \
    static type Get##name(lua_State* L, int index)                                                                                         \
    {                                                                                                                                      \
        if (!lua_isuserdata(L, index))                                                                                                     \
        {                                                                                                                                  \
            return nullptr;                                                                                                                \
        }                                                                                                                                  \
        type* userdata = (type*)lua_touserdata(L, index);                                                                                  \
        if (userdata == nullptr)                                                                                                           \
        {                                                                                                                                  \
            luaL_error(L, "Expected userdata for " #name);                                                                                 \
            return nullptr;                                                                                                                \
        }                                                                                                                                  \
        return *userdata;                                                                                                                  \
    }                                                                                                                                      \
    template<>                                                                                                                             \
    void ::Kyber::LuaUtils::Push<type>(lua_State * L, type value)                                                                          \
    {                                                                                                                                      \
        if (value == nullptr)                                                                                                              \
        {                                                                                                                                  \
            lua_pushnil(L);                                                                                                                \
            return;                                                                                                                        \
        }                                                                                                                                  \
                                                                                                                                           \
        Wrap##name(L, value);                                                                                                              \
    }                                                                                                                                      \
    static const luaL_Reg s_##name##Meta[] = {

#define KB_LUA_FUNCTION(name, func) { name, &func },

#define KB_LUA_END_TABLE(name)                                                                                                             \
    {                                                                                                                                      \
        nullptr, nullptr                                                                                                                   \
    }                                                                                                                                      \
    }                                                                                                                                      \
    ;                                                                                                                                      \
    static void Register##name(lua_State* L)                                                                                               \
    {                                                                                                                                      \
        luaL_newmetatable(L, #name);                                                                                                       \
        luaL_setfuncs(L, s_##name##Meta, 0);                                                                                               \
    }

class LuaUtils
{
public:
    static void RegisterFunctionTable(lua_State* L, const char* tableName, const luaL_Reg* functions)
    {
        lua_newtable(L);
        luaL_setfuncs(L, functions, 0);
        lua_setglobal(L, tableName);
    }

    template<typename T>
    static void Push(lua_State* L, T value);

    template<typename T>
    static T Pop(lua_State* L);

    // Helper function to pop individual elements from the Lua stack into a tuple
    template<typename Tuple, std::size_t... Indices>
    static void PopTupleImpl(lua_State* L, Tuple& tuple, std::index_sequence<Indices...>)
    {
        // Unpack the tuple and call Pop for each element
        ((std::get<Indices>(tuple) = Pop<std::tuple_element_t<Indices, Tuple>>(L)), ...);
    }

    // Main function to pop a tuple from the Lua stack
    template<typename... Args>
    static void PopTuple(lua_State* L, std::tuple<Args...>& tuple)
    {
        // Create an index sequence for the tuple elements
        PopTupleImpl(L, tuple, std::index_sequence_for<Args...>{});
    }

    static std::recursive_mutex& GetLock()
    {
        return s_lock;
    }

private:
    static std::recursive_mutex s_lock;
};

#define KB_LUA_LOCK std::lock_guard<std::recursive_mutex> lock(LuaUtils::GetLock())
} // namespace Kyber
