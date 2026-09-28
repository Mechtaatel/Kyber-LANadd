// Copyright Armchair Developers. Licensed under GPLv3.
#include <Network/LanAddress.h>

#include <winsock2.h>
#include <iphlpapi.h>
#include <vector>

namespace Kyber
{
static bool HasRadminAdapter()
{
    ULONG size = 0;
    if (GetIpAddrTable(nullptr, &size, FALSE) != ERROR_INSUFFICIENT_BUFFER)
    {
        return false;
    }

    std::vector<unsigned char> buffer(size);
    auto table = reinterpret_cast<MIB_IPADDRTABLE*>(buffer.data());
    if (GetIpAddrTable(table, &size, FALSE) != NO_ERROR)
    {
        return false;
    }

    for (DWORD i = 0; i < table->dwNumEntries; ++i)
    {
        if ((ntohl(table->table[i].dwAddr) >> 24) == 26)
        {
            return true;
        }
    }

    return false;
}

bool IsLanPeer(uint32_t address)
{
    const uint32_t ip = ntohl(address);
    if ((ip >> 24) != 26)
    {
        return IsLanIPv4(ip);
    }

    // Avoid enumerating adapters for every gameplay packet. Thread-local state
    // keeps socket and game threads independent; adapter changes expire quickly.
    thread_local uint64_t nextCheck = 0;
    thread_local bool hasRadminAdapter = false;
    const uint64_t now = GetTickCount64();
    if (now >= nextCheck)
    {
        hasRadminAdapter = HasRadminAdapter();
        nextCheck = now + 5000;
    }

    return IsLanIPv4(ip, hasRadminAdapter);
}
}
