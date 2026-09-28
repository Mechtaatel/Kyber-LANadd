// Copyright Armchair Developers. Licensed under GPLv3.
#include <Core/Program.h>
#include <Core/Server.h>
#include <Network/LanAddress.h>
#include <Utilities/PlatformUtils.h>
#include <ws2tcpip.h>
#include <cstring>
#include <unordered_map>

namespace Kyber
{
// The query contains a random 16-byte nonce, echoed before the Server protobuf.
static constexpr char kLanMagic[] = "KYBER-LAN-1:";
static constexpr int kQuerySize = sizeof(kLanMagic) - 1 + 16;
static constexpr uint16_t kDiscoveryPort = 25202;

void Server::CloseLanDiscovery()
{
    if (m_lanSocket != INVALID_SOCKET)
    {
        closesocket(m_lanSocket);
        m_lanSocket = INVALID_SOCKET;
    }
}

void Server::PollLanDiscovery()
{
    if (!IsRunning() || !m_creationInfo || !m_levelLoaded || !m_playerManager ||
        PlatformUtils::GetEnv("KYBER_LAN_DISCOVERY", "1") == "0")
    {
        CloseLanDiscovery();
        return;
    }

    if (m_lanSocket == INVALID_SOCKET)
    {
        if (GetTickCount64() < m_lanNextResponse)
        {
            return;
        }
        m_lanNextResponse = GetTickCount64() + 5000;
        m_lanSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (m_lanSocket == INVALID_SOCKET)
        {
            return;
        }
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(kDiscoveryPort);
        address.sin_addr.s_addr = INADDR_ANY;
        u_long nonBlocking = 1;
        if (bind(m_lanSocket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
            ioctlsocket(m_lanSocket, FIONBIO, &nonBlocking) != 0)
        {
            KYBER_LOG(Warning, "[LAN] Cannot bind UDP discovery port 25202: " << WSAGetLastError());
            CloseLanDiscovery();
            return;
        }
        m_lanNextResponse = 0;
        KYBER_LOG(Info, "[LAN] Discovery listening on UDP 25202");
    }

    // Rate limit per source: one adapter/client must not starve all others.
    static std::unordered_map<uint32_t, uint64_t> lastReplies;
    const auto now = GetTickCount64();
    for (auto it = lastReplies.begin(); it != lastReplies.end();)
    {
        if (now - it->second > 1000)
        {
            it = lastReplies.erase(it);
        }
        else
        {
            ++it;
        }
    }
    // Bound work on the game thread and limit discovery response amplification.
    for (int i = 0; i < 8; ++i)
    {
        char query[kQuerySize + 1];
        sockaddr_in peer{};
        int peerSize = sizeof(peer);
        const int length = recvfrom(m_lanSocket, query, sizeof(query), 0,
            reinterpret_cast<sockaddr*>(&peer), &peerSize);
        if (length == SOCKET_ERROR)
        {
            return;
        }
        if (length != kQuerySize || std::memcmp(query, kLanMagic, sizeof(kLanMagic) - 1) != 0 ||
            !IsLanPeer(peer.sin_addr.s_addr))
        {
            continue;
        }
        const auto previous = lastReplies.find(peer.sin_addr.s_addr);
        if ((previous != lastReplies.end() && now - previous->second < 50) ||
            (previous == lastReplies.end() && lastReplies.size() >= 256))
        {
            continue;
        }
        lastReplies[peer.sin_addr.s_addr] = now;
        kyber_api::Server server;
        server.set_id(m_serverId);
        server.set_name(m_creationInfo->name);
        server.set_description(m_creationInfo->description);
        server.set_creator("LAN host");
        server.mutable_levelsetup()->set_map(m_currentLevel);
        server.mutable_levelsetup()->set_mode(m_currentMode);
        server.set_maxplayercount(m_creationInfo->maxPlayers);
        uint32_t players = 0;
        for (ServerPlayer* player : m_playerManager->m_players)
        {
            if (player != nullptr && !player->IsAIPlayer())
            {
                ++players;
            }
        }
        server.set_playercount(players);
        server.set_port(Settings<NetworkSettings>("Network")->ServerPort);
        server.set_region("LAN");
        server.set_requirespassword(!m_creationInfo->password.empty());
        (*server.mutable_meta())["lan_only"] = m_onlineMode ? "0" : "1";
        for (const auto& mod : g_program->m_modData.serverMods)
        {
            server.add_mods()->CopyFrom(mod);
        }
        const std::string reply = std::string(query, kQuerySize) + server.SerializeAsString();
        if (reply.size() <= 60000)
        {
            sendto(m_lanSocket, reply.data(), static_cast<int>(reply.size()), 0,
                reinterpret_cast<sockaddr*>(&peer), peerSize);
        }
    }
}
} // namespace Kyber
