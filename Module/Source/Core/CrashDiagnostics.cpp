#include <Core/CrashDiagnostics.h>
#include <DbgHelp.h>
#include <filesystem>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <initializer_list>

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

// Private minidump stream KYB1. Fixed-size storage avoids allocation on a fault.
// Each entry describes at most 512 bytes, plus the page state and read result.
struct MemoryEvidence
{
    uint64_t address;
    uint32_t size, error, state, protection;
    unsigned char bytes[512];
};
struct CrashEvidence
{
    uint32_t version = 1;
    uint32_t count = 0;
    MemoryEvidence entries[64]{};
} evidence;

void SnapshotAddress(uint64_t address)
{
    if (address < 0x10000 || evidence.count == 64) return;
    for (uint32_t i = 0; i < evidence.count; ++i)
        if (evidence.entries[i].address == address) return;
    auto& entry = evidence.entries[evidence.count++];
    entry.address = address;
    MEMORY_BASIC_INFORMATION region{};
    if (!VirtualQuery(reinterpret_cast<void*>(address), &region, sizeof(region)))
    {
        entry.error = GetLastError();
        return;
    }
    entry.state = region.State;
    entry.protection = region.Protect;
    if (region.State != MEM_COMMIT || (region.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return;
    const auto available = reinterpret_cast<uintptr_t>(region.BaseAddress) + region.RegionSize - address;
    const SIZE_T requested = available < sizeof(entry.bytes) ? available : sizeof(entry.bytes);
    SIZE_T copied = 0;
    const BOOL read = ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(address), entry.bytes, requested, &copied);
    entry.error = read ? ERROR_SUCCESS : GetLastError();
    entry.size = static_cast<uint32_t>(copied);
}

void SnapshotCrashMemory()
{
    const uint64_t addresses[] = {crashContext.Rax, crashContext.Rbx, crashContext.Rcx, crashContext.Rdx,
        crashContext.Rsi, crashContext.Rdi, crashContext.Rbp, crashContext.Rsp, crashContext.Rip,
        crashContext.R8, crashContext.R9, crashContext.R10, crashContext.R11, crashContext.R12,
        crashContext.R13, crashContext.R14, crashContext.R15};
    for (const auto address : addresses) SnapshotAddress(address);
    // The vtable's preceding slot identifies RTTI when the object is still valid.
    SnapshotAddress(crashContext.Rax >= 8 ? crashContext.Rax - 8 : 0);
    // Two pointer hops include object -> vtable -> code, and list -> element -> object.
    // No heap traversal: only pointer fields needed for the observed unload fault.
    uint32_t first = 0;
    for (unsigned depth = 0; depth < 2; ++depth)
    {
        const auto end = evidence.count;
        for (auto i = first; i < end; ++i)
        {
            const auto& entry = evidence.entries[i];
            for (const size_t offset : {size_t(0), size_t(0x10), size_t(0x30), size_t(0x50), size_t(0x80)})
            {
                if (offset + sizeof(uint64_t) > entry.size) continue;
                uint64_t pointer;
                std::memcpy(&pointer, entry.bytes + offset, sizeof(pointer));
                SnapshotAddress(pointer);
                if (offset == 0 && pointer >= 8) SnapshotAddress(pointer - 8);
            }
        }
        first = end;
    }
}

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
        MINIDUMP_USER_STREAM stream{0x4b594201, sizeof(evidence), &evidence};
        MINIDUMP_USER_STREAM_INFORMATION streams{1, &stream};
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
            dumpSucceeded = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, type, &info, &streams, nullptr) != FALSE;
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
    SnapshotCrashMemory();
    SetEvent(startEvent);
    if (WaitForSingleObject(doneEvent, 25000) != WAIT_OBJECT_0)
    {
        *error = ERROR_TIMEOUT;
        return false;
    }
    *error = dumpError;
    return dumpSucceeded;
}

void CaptureAbnormalProcessExit(DWORD code)
{
    if (!LocalCrashDumpsEnabled() || code == 0 || InterlockedCompareExchange(&capturing, 0, 0) != 0) return;
    CONTEXT context{};
    RtlCaptureContext(&context);
    // Synthetic record: an exit request, not a hardware exception.
    EXCEPTION_RECORD record{};
    record.ExceptionCode = 0xe0420001;
    record.ExceptionAddress = reinterpret_cast<void*>(context.Rip);
    record.NumberParameters = 1;
    record.ExceptionInformation[0] = code;
    EXCEPTION_POINTERS pointers{&record, &context};
    DWORD error;
    const wchar_t* path;
    CaptureLocalCrashDump(&pointers, &error, &path);
}
}
