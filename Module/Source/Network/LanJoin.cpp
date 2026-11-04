// Copyright Armchair Developers. Licensed under GPLv3.
#include <Network/LanJoin.h>
#include <Utilities/PlatformUtils.h>
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <bcrypt.h>

namespace Kyber
{
bool IndependentLanEnabled()
{
    return PlatformUtils::GetEnv("KYBER_LAN_INDEPENDENT", "0") == "1";
}

std::optional<uint64_t> CreateLanPlayerId()
{
    uint64_t random = 0;
    if (BCryptGenRandom(nullptr, reinterpret_cast<PUCHAR>(&random), sizeof(random),
            BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
        return std::nullopt;
    // Session-only identity: never accept the EA/Kyber ID claimed by a guest.
    return (uint64_t{1} << 61) | (random & ((uint64_t{1} << 60) - 1));
}
} // namespace Kyber
