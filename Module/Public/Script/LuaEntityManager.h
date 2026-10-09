// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <Script/LuaEventManager.h>

#include <SDK/TypeInfo.h>

namespace Kyber
{
class LuaEntityManager
{
    friend class ScriptManager;

public:
    static const NativeEntity** WrapEntity(NativeEntity* entity);
    static const EntityBus** WrapEntityBus(EntityBus* entity);

    static NativeEntity* GetEntity(int index);
    static EntityBus* GetEntityBus(int index);

private:
    static void Register(lua_State* lua);

    static lua_State* s_lua;
};
} // namespace Kyber
