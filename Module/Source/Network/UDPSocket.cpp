// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <Network/UDPSocket.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Network/SocketManager.h>
#include <Network/LanAddress.h>
#include <Network/LanJoin.h>
#include <Network/ProxyRoute.h>
#include <Utilities/ErrorUtils.h>
#include <Utilities/PlatformUtils.h>
#include <Utilities/StringUtils.h>
#include <SDK/Funcs.h>

#include <ws2tcpip.h>

#ifdef SIMULATE_OLD_PROXY
    #include <nlohmann/json.hpp>
#endif

namespace Kyber
{
static thread_local uint8_t s_proxifyBuffer[3072];

std::string DirectionToString(ProtocolDirection direction)
{
    switch (direction)
    {
    case ProtocolDirection::Serverbound:
        return "Client";
    case ProtocolDirection::Clientbound:
        return "Server";
    }

    return "";
}

UDPSocket::UDPSocket(SocketCreator* creator, ProtocolDirection direction, SocketSpawnInfo info)
    : m_creator(creator)
    , m_socketHandle(INVALID_SOCKET)
    , m_port(0)
    , m_isBroadcasting(false)
    , m_blockingMode(false)
    , m_peerAddressIsValid(false)
    , m_direction(direction)
    , m_info(info)
{
    m_proxyQueue = std::make_shared<WebSocket::ReceiveQueue>();
}

UDPSocket::~UDPSocket() {}

void UDPSocket::Close()
{
    KYBER_LOG(Info, "[" << DirectionToString(m_direction) << "] Closing socket");

    if (m_socketHandle != INVALID_SOCKET)
    {
        shutdown(m_socketHandle, SD_BOTH);
        closesocket(m_socketHandle);
    }

    m_socketHandle = INVALID_SOCKET;
}

uint8_t* ProxifyBuffer(uint8_t* buffer, int& bufferSize, sockaddr* addr)
{
    bufferSize += 2;

    s_proxifyBuffer[0] = ((sockaddr_in*)addr)->sin_port >> 8;
    s_proxifyBuffer[1] = ((sockaddr_in*)addr)->sin_port;
    memcpy(s_proxifyBuffer + 2, buffer, bufferSize - 2);

    return s_proxifyBuffer;
}

bool UDPSocket::Send(uint8_t* buffer, int bufferSize, unsigned int flags)
{
    if (buffer == nullptr || bufferSize < 0 || !m_peerAddressIsValid || m_peerAddress.Length() < sizeof(sockaddr_in))
    {
        return false;
    }

    sockaddr* addr = (sockaddr*)m_peerAddress.Data();

    // KYBER_LOG(Info, "[" << DirectionToString(m_direction) << "] Sending " << bufferSize << " bytes to "
    //                     << inet_ntoa(((sockaddr_in*)addr)->sin_addr) << ":" << ntohs(((sockaddr_in*)addr)->sin_port));

    // isProxied describes the outgoing client connection, not every socket
    // subsequently used by the local frontend. Server replies use the virtual
    // peer address instead; a real LAN/loopback peer must stay on UDP.
    const int proxyIndex = SelectProxySocket(m_direction, m_info.isProxied, ntohl(((sockaddr_in*)addr)->sin_addr.s_addr));
    if (proxyIndex >= 0)
    {
        if (static_cast<std::size_t>(proxyIndex) >= m_sockets.size())
        {
            KYBER_LOG(Error, "Invalid proxy index: " << proxyIndex);
            return false;
        }

        bool proxify = m_direction == ProtocolDirection::Clientbound;
        if (proxify)
        {
            if (!ValidProxyPayload(bufferSize, sizeof(s_proxifyBuffer)))
            {
                KYBER_LOG(Error, "Proxy payload exceeds packet buffer: " << bufferSize);
                return false;
            }
            buffer = ProxifyBuffer(buffer, bufferSize, addr);
        }

        bool success = m_sockets[proxyIndex].Send(buffer, bufferSize);
        if (!success)
        {
            // We are probably connecting or reconnecting, so we can just tell the engine this
            // was successful. It's built for UDP, so it'll handle the packet loss for us.

            // In the future, if it becomes a problem, it may be worth implementing a timeout for
            // proxy reconnections, and letting the client bail if things aren't working.
            return true;
        }
        
        return true;
    }

    if (sendto(m_socketHandle, reinterpret_cast<const char*>(buffer), bufferSize, 0, addr, sizeof(sockaddr_in)) < 0)
    {
        int error = WSAGetLastError();
        if (error != WSAEWOULDBLOCK)
        {
            KYBER_LOG(Error, "[" << DirectionToString(m_direction) << "] Failed to send data: " << error);
            return false;
        }

        return true;
    }

#ifdef _DEBUG
    KYBER_LOG(Trace, "[" << DirectionToString(m_direction) << "] Sent " << bufferSize << " bytes");
#endif

    return true;
}

// Discovery is multiplexed on the bound game socket. Consume only our framed
// requests; Frostbite never sees them or adopts the browser's reply address.
bool UDPSocket::HandleDiscovery(const uint8_t* data, int size, const sockaddr_in& peer)
{
    static constexpr char magic[] = "KYBER-LAN-1:";
    constexpr int querySize = sizeof(magic) - 1 + 16;
    constexpr int challengeSize = querySize + sizeof(uint64_t);
    if ((size != querySize && size != challengeSize) || memcmp(data, magic, sizeof(magic) - 1) != 0)
        return false;

    const bool local = IsLanPeer(peer.sin_addr.s_addr);
    if (!local && !g_program->m_server->m_onlineMode && !IndependentLanEnabled()) return true;
    const auto now = GetTickCount64();
    if (now >= m_discoveryCleanup)
    {
        for (auto it = m_discoveryPeers.begin(); it != m_discoveryPeers.end();)
        {
            if (now - it->second.lastRequest >= 2000) it = m_discoveryPeers.erase(it);
            else ++it;
        }
        m_discoveryCleanup = now + 1000;
    }
    const uint64_t endpoint = (uint64_t{peer.sin_addr.s_addr} << 16) | peer.sin_port;
    if (m_discoveryPeers.find(endpoint) == m_discoveryPeers.end() && m_discoveryPeers.size() >= 256) return true;
    auto& state = m_discoveryPeers[endpoint];
    const auto* dest = reinterpret_cast<const sockaddr*>(&peer);
    if (size == challengeSize)
    {
        if (local || !state.cookie || now - state.lastRequest >= 2000 ||
            memcmp(data + querySize, &state.cookie, sizeof(state.cookie)) != 0) return true;
        state.cookie = 0;
    }
    else
    {
        if (state.lastRequest && now - state.lastRequest < 50) return true;
        state.lastRequest = now;
        if (!local)
        {
            // Confirm the return path before sending a potentially large mod list.
            state.cookie = CreateLanPlayerId().value_or(0);
            if (!state.cookie) return true;
            std::string challenge(reinterpret_cast<const char*>(data), querySize);
            challenge.append(reinterpret_cast<const char*>(&state.cookie), sizeof(state.cookie));
            sendto(m_socketHandle, challenge.data(), challengeSize, 0, dest, sizeof(peer));
            return true;
        }
    }

    auto snapshot = g_program->m_server->DiscoverySnapshot();
    if (!snapshot.empty())
    {
        snapshot.insert(0, reinterpret_cast<const char*>(data), querySize);
        sendto(m_socketHandle, snapshot.data(), static_cast<int>(snapshot.size()), 0, dest, sizeof(peer));
    }
    return true;
}

int UDPSocket::ReceiveDatagram(uint8_t* buffer, int bufferSize, sockaddr_in& peer)
{
    if (m_socketHandle == INVALID_SOCKET) return -1;

    for (int consumed = 0; consumed < 8; ++consumed)
    {
        int addressSize = sizeof(peer);
        const int size = recvfrom(m_socketHandle, reinterpret_cast<char*>(buffer), bufferSize, 0,
            reinterpret_cast<sockaddr*>(&peer), &addressSize);
        if (size == SOCKET_ERROR)
        {
            const int error = WSAGetLastError();
            if (error != WSAEWOULDBLOCK) KYBER_LOG(Debug, "Error receiving data: " << error);
            return -1;
        }

        if (m_direction != ProtocolDirection::Clientbound) return size;
        if (HandleDiscovery(buffer, size, peer))
        {
            if (m_blockingMode) return -1;
            continue;
        }
        if (!g_program->m_server->m_onlineMode && !IndependentLanEnabled() && !IsLanPeer(peer.sin_addr.s_addr))
            return -1;
        return size;
    }
    return -1;
}

int UDPSocket::ReceiveFromWhen(uint8_t* buffer, int bufferSize, unsigned int& when)
{
    // A hybrid host can have a backlog on either transport. After a relayed
    // packet, give the nonblocking UDP socket the next turn.
    const bool directFirst = m_preferDirectReceive && !m_blockingMode;
    const bool canReceiveProxy = m_direction == ProtocolDirection::Clientbound || m_info.isProxied;
    auto message = canReceiveProxy && !directFirst ? m_proxyQueue->tryDequeue() : std::nullopt;
    sockaddr_in peer{};
    if (!message)
    {
        const int size = ReceiveDatagram(buffer, bufferSize, peer);
        if (size >= 0)
        {
            when = NetTick();
            m_peerAddress.SetData(&peer, sizeof(peer));
            m_peerAddressIsValid = true;
            m_preferDirectReceive = false;
            return size;
        }
        if (!directFirst) return -1;
        message = m_proxyQueue->tryDequeue();
        if (!message) return -1;
    }

    auto* packet = *message;
    int size = std::min(bufferSize, static_cast<int>(packet->size));
    const auto proxyId = packet->socketId;
    when = packet->timestamp;
    memcpy(buffer, packet->data, size);
    FB_GLOBAL_ARENA->del(packet);

    if (m_direction == ProtocolDirection::Clientbound)
    {
        m_preferDirectReceive = true;
        if (size < 2 || proxyId > 255)
        {
            KYBER_LOG(Warning, "Discarding malformed proxy datagram");
            return -1;
        }
        peer.sin_family = AF_INET;
        peer.sin_addr.s_addr = htonl(0x00010100u | proxyId);
        peer.sin_port = buffer[0] << 8 | buffer[1];
        m_peerAddress.SetData(&peer, sizeof(peer));
        m_peerAddressIsValid = true;
        size -= 2;
        std::memmove(buffer, buffer + 2, size);
    }
    return size;
}

bool UDPSocket::Listen(const SocketAddr& address, bool blocking)
{
    m_socketHandle = INVALID_SOCKET;

    sockaddr_in* addr = (sockaddr_in*)address.Data();
    if ((m_socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == INVALID_SOCKET)
    {
        KYBER_LOG(Error, "Failed to create socket (" << WSAGetLastError() << ")");
        return false;
    }

    if (bind(m_socketHandle, (sockaddr*)addr, sizeof(sockaddr_in)) != 0)
    {
        int error = WSAGetLastError();
        Close();
        KYBER_LOG(Error, "Failed to bind socket (" << error << ")");
        return false;
    }

    if (!SetBlockingMode(blocking))
    {
        Close();
        KYBER_LOG(Error, "Failed to set blocking mode of socket");
        return false;
    }

    m_port = ntohs(addr->sin_port);
    m_address = address;

    KYBER_LOG(Trace, "Created listening socket");

    m_sockets.clear();

    if (m_info.isProxied && m_direction == ProtocolDirection::Serverbound)
    {
        m_sockets.push_back(WebSocket("client", 0, m_proxyQueue));
        m_sockets.back().ConnectAsClient(m_info.proxyAddress, g_program->m_client->m_joinToken);
    }
    else if (m_direction == ProtocolDirection::Clientbound && g_program->m_server->IsRunning() && g_program->m_server->m_onlineMode)
    {
        const char* pinnedProxy = std::getenv("KYBER_PINNED_PROXY");
        if (pinnedProxy != nullptr)
        {
            m_sockets.push_back(WebSocket("pinned", 0, m_proxyQueue));
            m_sockets.back().ConnectAsServer(pinnedProxy, g_program->m_client->m_joinToken);
        }
        else
        {
            auto proxies = g_program->GetAPI()->GetProxy()->GetList();
            m_sockets.reserve(proxies.size());

            uint32_t id = 0;
            for (const auto& proxy : proxies)
            {
                m_sockets.push_back(WebSocket(proxy.id(), id++, m_proxyQueue));
                m_sockets.back().ConnectAsServer(proxy.ip(), g_program->m_client->m_joinToken);
            }
        }
    }

    return true;
}

void UDPSocket::UpdateProxies(const eastl::vector<kyber_api::ProxyInfo>& newList)
{
    for (const auto& proxyInfo : newList)
    {
        bool seen = false;
        for (const auto& proxy : m_sockets) 
        {
            if (proxy.GetId() == proxyInfo.id())
            {
                seen = true;
                break;
            }
        }

        if (!seen)
        {
            m_sockets.push_back(WebSocket(proxyInfo.id(), m_sockets.size(), m_proxyQueue));
            m_sockets.back().ConnectAsServer(proxyInfo.ip(), g_program->m_client->m_joinToken);
        }
    }
}

void UDPSocket::ReconnectProxies()
{
    if (m_direction != ProtocolDirection::Clientbound)
    {
        return;
    }

    KYBER_LOG(Info, "[Network] Reconnecting to " << m_sockets.size() << " proxies");

    for (auto& proxy : m_sockets)
    {
        proxy.Reconnect(g_program->m_client->m_joinToken);
    }
}

bool UDPSocket::Connect(const SocketAddr& address, bool blocking)
{
    return false;
}

bool UDPSocket::Create(bool blocking)
{
    return false;
}

bool UDPSocket::SetBlockingMode(bool blocking)
{
    m_blockingMode = blocking;
    if (m_socketHandle == INVALID_SOCKET)
    {
        return true;
    }

    u_long mode = blocking ? 0 : 1;
    if (ioctlsocket(m_socketHandle, FIONBIO, &mode) == SOCKET_ERROR)
    {
        return false;
    }

    int bufferSize = 600000;
    if (setsockopt(m_socketHandle, SOL_SOCKET, SO_SNDBUF, (char*)&bufferSize, sizeof(bufferSize)) == SOCKET_ERROR)
    {
        return false;
    }

    if (setsockopt(m_socketHandle, SOL_SOCKET, SO_RCVBUF, (char*)&bufferSize, sizeof(bufferSize)) == SOCKET_ERROR)
    {
        return false;
    }

    return true;
}

void UDPSocket::SetPeerAddress(const SocketAddr& address)
{
    m_peerAddress = address;
    m_peerAddressIsValid = true;
}

SocketAddr UDPSocket::PeerAddress() const
{
    return m_peerAddress;
}

bool UDPSocket::SetBroadcast(uint16_t port)
{
    KYBER_LOG(Trace, "Setting broadcast port to " << port);
    return false;
}

bool UDPSocket::BlockingMode() const
{
    return false;
}

intptr_t UDPSocket::NativeSocket() const
{
    return m_socketHandle;
}

int UDPSocket::Port() const
{
    return m_port;
}

const SocketAddr* UDPSocket::Address() const
{
    return &m_address;
}

bool UDPSocket::SetDefaultPacketInfo(PacketInfo* info)
{
    if (!info)
    {
        KYBER_LOG(Error, "Invalid packet info");
        return false;
    }

    info->minSize = 1;
    info->maxSize = 1264;
    info->recommendedSize = info->maxSize;
    info->overheadWhenAligned = 28;
    info->alignment = 1;
    return true;
}
} // namespace Kyber
