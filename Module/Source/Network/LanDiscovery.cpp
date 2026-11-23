// Copyright Armchair Developers. Licensed under GPLv3.
#include <Core/Program.h>
#include <Core/Server.h>
#include <Network/LanJoin.h>
#include <Utilities/PlatformUtils.h>

namespace Kyber
{
void Server::CloseLanDiscovery()
{
    std::lock_guard lock(m_discoveryMutex);
    m_discoverySnapshot.clear();
    m_nextDiscoverySnapshot = 0;
}

std::string Server::DiscoverySnapshot()
{
    std::lock_guard lock(m_discoveryMutex);
    return m_discoverySnapshot;
}

void Server::FillBrowserInfo(kyber_api::Server& server) const
{
    if (!m_creationInfo) return;
    server.set_id(m_serverId);
    server.set_name(m_creationInfo->name);
    server.set_description(m_creationInfo->description);
    server.set_creator(m_creationInfo->hostName.empty() ? "LAN host" : m_creationInfo->hostName);
    auto* level = server.mutable_levelsetup();
    level->set_map(m_currentLevel);
    level->set_mode(m_currentMode);
    for (const auto& entry : m_mapRotation.GetList())
    {
        if (entry.level == m_currentLevel && entry.mode == m_currentMode)
        {
            level->set_mapname(entry.mapName);
            level->set_modename(entry.modeName);
            break;
        }
    }
    server.set_maxplayercount(m_creationInfo->maxPlayers);
    uint32_t players = 0;
    if (m_playerManager)
    {
        for (ServerPlayer* player : m_playerManager->m_players)
        {
            if (player != nullptr && !player->IsAIPlayer() && !player->IsSpectator()) ++players;
        }
    }
    server.set_playercount(players);
    server.set_port(Settings<NetworkSettings>("Network")->ServerPort);
    server.set_region("LAN");
    server.set_requirespassword(!m_creationInfo->password.empty());
    (*server.mutable_meta())["lan_only"] = m_onlineMode ? "0" : "1";
    for (const auto& mod : g_program->m_modData.serverMods) server.add_mods()->CopyFrom(mod);
}

void Server::PollLanDiscovery()
{
    if (!IsRunning() || !m_creationInfo || !m_levelLoaded || !m_playerManager ||
        PlatformUtils::GetEnv("KYBER_LAN_DISCOVERY", "1") == "0")
    {
        CloseLanDiscovery();
        return;
    }

    const auto now = GetTickCount64();
    std::lock_guard lock(m_discoveryMutex);
    if (now < m_nextDiscoverySnapshot) return;

    // Only the game thread reads Frostbite objects. Socket threads serve a copy.
    kyber_api::Server server;
    FillBrowserInfo(server);
    (*server.mutable_meta())["lan_shared_port"] = "1";
    if (IndependentLanEnabled() && m_creationInfo->password.empty())
    {
        (*server.mutable_meta())["lan_only"] = "1";
    }
    auto snapshot = server.SerializeAsString();
    m_discoverySnapshot = snapshot.size() <= 59972 ? std::move(snapshot) : std::string();
    m_nextDiscoverySnapshot = now + 1000;
}
} // namespace Kyber
