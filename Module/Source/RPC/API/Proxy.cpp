// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
#include <RPC/API/Proxy.h>
#include <chrono>

#include <Base/Log.h>

namespace Kyber
{
using grpc::ClientContext;
using grpc::Status;

ProxyAPI::ProxyAPI(std::shared_ptr<Channel> channel, std::string token)
    : m_stub(Proxy::NewStub(channel))
    , m_token(token)
{}

std::vector<ProxyInfo> ProxyAPI::GetList() const
{
    ClientContext context;
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(4));

    kyber_common::Empty request;

    ProxyList response;
    Status status = m_stub->GetList(&context, request, &response);
    if (!status.ok())
    {
        KYBER_LOG(Error, "[RPC] RPC error while retrieving stats (" << status.error_message() << ")");
        return std::vector<ProxyInfo>();
    }

    std::vector<ProxyInfo> list;
    for (const auto& info : response.proxies())
    {
        list.push_back(info);
    }
    return list;
}
} // namespace Kyber
