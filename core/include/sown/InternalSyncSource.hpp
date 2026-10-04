#pragma once
#include "ISyncSource.hpp"
#include <chrono>
#include <mutex>

namespace sown {
class InternalSyncSource final : public ISyncSource {
public:
    bool start() override;
    void stop() override;
    bool isConnected() const override;
    SyncState getState() const override;

    void play();
    void pause();
    void seek(TimeNs position);
    void reset();
private:
    using Clock = std::chrono::steady_clock;
    mutable std::mutex mutex_;
    bool connected_{false};
    TransportState transport_{TransportState::Stopped};
    TimeNs basePosition_{0};
    Clock::time_point anchor_{Clock::now()};
    std::uint64_t sequence_{0};
    TimeNs positionUnlocked(Clock::time_point now) const;
};
}
