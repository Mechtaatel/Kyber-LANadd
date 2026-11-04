#pragma once
#include <Windows.h>
#include <string>
namespace Kyber
{
bool InitializeLocalCrashDumps(const std::wstring& directory);
bool LocalCrashDumpsEnabled();
// The pre-created worker receives private copies of the fault context.
bool CaptureLocalCrashDump(const EXCEPTION_POINTERS* exception, DWORD* error, const wchar_t** path);
}
