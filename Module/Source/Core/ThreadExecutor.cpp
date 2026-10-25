// Copyright Armchair Developers. Licensed under GPLv3.

#include <Core/Memory.h>
#include <Core/ThreadExecutor.h>

namespace Kyber
{
ThreadExecutor* g_threadExecutor;

void ThreadExecutor::QueueDelayTicks(GameThread thread, uint32_t delayTicks, Func func)
{
    auto dataGuard = m_threadData[thread].Lock();
    dataGuard->delayedFuncs.push_back({dataGuard->tickCount + delayTicks, func});
}

void ThreadExecutor::QueueDelaySecs(GameThread thread, float delaySeconds, Func func)
{
    QueueDelayTicks(thread, static_cast<uint32_t>(delaySeconds * 30.0f), func);
}

void ThreadExecutor::Process(GameThread thread)
{
    eastl::vector<Func> ready;
    {
        auto dataGuard = m_threadData[thread].Lock();
        auto& delayedFuncs = dataGuard->delayedFuncs;
        delayedFuncs.erase(eastl::remove_if(delayedFuncs.begin(), delayedFuncs.end(),
            [&ready, tickCount = dataGuard->tickCount](DelayedFunc& delayedFunc) {
                if (tickCount < delayedFunc.targetTicks)
                {
                    return false;
                }
                ready.push_back(std::move(delayedFunc.func));
                return true;
            }), delayedFuncs.end());
        dataGuard->tickCount++;
    }

    // A callback can queue more work on this thread. Run it after releasing
    // the queue lock, and leave newly queued work for a later Process call.
    for (auto& func : ready)
    {
        func();
    }
}

void ThreadExecutor::StaticInit()
{
    static ThreadExecutor staticThreadExecutor;
    g_threadExecutor = &staticThreadExecutor;
}
} // namespace Kyber
