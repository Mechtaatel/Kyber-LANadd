#include <Core/CrashDiagnostics.h>
#include <DbgHelp.h>
#include <filesystem>
#include <cstdio>

namespace Kyber
{
namespace
{
HANDLE startEvent, doneEvent;
std::wstring dumpDirectory;
CONTEXT crashContext{};
EXCEPTION_RECORD crashRecord{};
DWORD crashThread, dumpError;
bool dumpSucceeded;
wchar_t dumpPath[MAX_PATH]{};
volatile LONG capturing = 0;

DWORD WINAPI DumpWorker(void*)
{
    for (;;)
    {
        if (WaitForSingleObject(startEvent, INFINITE) != WAIT_OBJECT_0) return 1;
        SYSTEMTIME now{};
        GetSystemTime(&now);
        swprintf_s(dumpPath, L"%s\\kyber-%04u%02u%02uT%02u%02u%02u-%03u-p%lu-t%lu.dmp",
            dumpDirectory.c_str(), now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
            now.wSecond, now.wMilliseconds, GetCurrentProcessId(), crashThread);
        EXCEPTION_POINTERS pointers{&crashRecord, &crashContext};
        MINIDUMP_EXCEPTION_INFORMATION info{crashThread, &pointers, FALSE};
        dumpSucceeded = false;
        dumpError = ERROR_SUCCESS;
        // Stacks/modules and memory-region metadata, never a full heap dump.
        const MINIDUMP_TYPE types[] = {
            static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules | MiniDumpWithFullMemoryInfo),
            MiniDumpNormal,
        };
        for (const auto type : types)
        {
            HANDLE file = CreateFileW(dumpPath, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                FILE_ATTRIBUTE_NORMAL, nullptr);
            if (file == INVALID_HANDLE_VALUE) { dumpError = GetLastError(); break; }
            dumpSucceeded = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, type, &info, nullptr, nullptr) != FALSE;
            dumpError = dumpSucceeded ? ERROR_SUCCESS : GetLastError();
            FlushFileBuffers(file);
            CloseHandle(file);
            if (dumpSucceeded) break;
            DeleteFileW(dumpPath);
        }
        SetEvent(doneEvent);
    }
}
}

bool InitializeLocalCrashDumps(const std::wstring& directory)
{
    if (startEvent) return true;
    if (directory.empty() || directory.size() > MAX_PATH - 85) return false;
    std::error_code error;
    std::filesystem::create_directories(directory, error);
    if (error) return false;
    dumpDirectory = directory;
    startEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    doneEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!startEvent || !doneEvent)
    {
        if (startEvent) CloseHandle(startEvent);
        if (doneEvent) CloseHandle(doneEvent);
        startEvent = doneEvent = nullptr;
        return false;
    }
    HANDLE worker = CreateThread(nullptr, 0, DumpWorker, nullptr, 0, nullptr);
    if (!worker) { CloseHandle(startEvent); CloseHandle(doneEvent); startEvent = doneEvent = nullptr; return false; }
    CloseHandle(worker);
    return true;
}

bool LocalCrashDumpsEnabled() { return startEvent != nullptr; }

bool CaptureLocalCrashDump(const EXCEPTION_POINTERS* exception, DWORD* error, const wchar_t** path)
{
    *path = dumpPath;
    *error = ERROR_INVALID_PARAMETER;
    if (!startEvent || !exception || !exception->ContextRecord || !exception->ExceptionRecord) return false;
    if (InterlockedCompareExchange(&capturing, 1, 0) != 0) { *error = ERROR_BUSY; return false; }
    crashContext = *exception->ContextRecord;
    crashRecord = *exception->ExceptionRecord;
    crashThread = GetCurrentThreadId();
    SetEvent(startEvent);
    if (WaitForSingleObject(doneEvent, 25000) != WAIT_OBJECT_0)
    {
        *error = ERROR_TIMEOUT;
        return false;
    }
    *error = dumpError;
    return dumpSucceeded;
}
}
