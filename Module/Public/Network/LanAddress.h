// Copyright Armchair Developers. Licensed under GPLv3.
#pragma once

#include <cstdint>

namespace Kyber
{
// Host byte order. Radmin's public 26/8 range is allowed only on that overlay.
inline bool IsLanIPv4(uint32_t ip, bool hasRadminAdapter = false)
{
    return (ip >> 24) == 10 || (ip >> 24) == 127 || (ip >> 20) == 0xac1 ||
        (ip >> 16) == 0xc0a8 || (ip >> 16) == 0xa9fe ||
        ((ip >> 24) == 26 && hasRadminAdapter);
}

// Network byte order, for both discovery and gameplay datagrams.
bool IsLanPeer(uint32_t address);
}
