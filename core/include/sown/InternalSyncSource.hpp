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
private:
    mutable std::mutex mutex_;
    bool running_{false};
    TransportState transport_{TransportState::Stopped};
    TimeNs anchorPosition_{0};
    std::chrono::steady_clock::time_point anchorTime_{};
    std::uint64_t sequence_{0};
};
}
