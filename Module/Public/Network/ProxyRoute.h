// Copyright Armchair Developers. Licensed under GPLv3.

#pragma once

#include <Network/SocketCreator.h>

#include <cstddef>
#include <cstdint>

namespace Kyber
{
// The proxy receive path represents remote peers as 0.1.1.<socket index>.
// Addresses here are host-order IPv4 values, not strings or network-order words.
constexpr int ProxyPeerIndex(uint32_t address)
{
    return (address & 0xFFFFFF00u) == 0x00010100u ? static_cast<int>(address & 0xFFu) : -1;
}

constexpr int SelectProxySocket(ProtocolDirection direction, bool proxiedClient, uint32_t address)
{
    return direction == ProtocolDirection::Clientbound ? ProxyPeerIndex(address) : (proxiedClient ? 0 : -1);
}

constexpr bool ValidProxyPayload(int size, std::size_t capacity)
{
    return size >= 0 && capacity >= 2 && static_cast<std::size_t>(size) <= capacity - 2;
}
} // namespace Kyber
