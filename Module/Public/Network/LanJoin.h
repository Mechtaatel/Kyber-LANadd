// Copyright Armchair Developers. Licensed under GPLv3.
#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace Kyber
{
constexpr bool IsIndependentLanPlayer(uint64_t id)
{
    return (id >> 60) == 2;
}

// Released LAN ADD clients use the game's original display-name join message.
// Account authentication messages must never be accepted as guest names.
inline bool IsLanJoinName(const std::string& name)
{
    if (name.empty() || name.size() > 64 || name.find_first_not_of(' ') == std::string::npos ||
        name.rfind("KyberAuthentication:", 0) == 0 || name.rfind("KyberLanAuthentication:", 0) == 0)
        return false;
    for (const unsigned char ch : name)
        if (ch < 32 || ch == 127) return false;
    return true;
}

bool IndependentLanEnabled();
std::optional<uint64_t> CreateLanPlayerId();
} // namespace Kyber
