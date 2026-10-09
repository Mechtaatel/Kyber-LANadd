// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <Windows.h>

#include <filesystem>
#include <string>

namespace Kyber
{
class PlatformUtils
{
public:
    static std::filesystem::path GetModulePath();
    static std::filesystem::path GetProgramDataPath();
    static std::string GetEnv(const std::string& env, const std::string& def = "");
    static uintptr_t BaseAddress();
    static void* GetVTableFunction(const void* pVtable, int offset);
    static void* HookVTableFunction(void* pVtable, void* fnHookFunc, int offset);
    static void* DuplicateVTable(void* objectPtr, size_t numVirtualFunctions = 106 /* Entity Vtable Function Count */);

private:
    static BOOL MaskCompare(PVOID pBuffer, LPCSTR lpPattern, LPCSTR lpMask);
};
} // namespace Kyber