#pragma once
#include "Cue.hpp"
#include "ISyncSource.hpp"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

namespace sown {
enum class SyncQuality { NoSignal, Excellent, Good, Unstable };

struct PrecisionStats {
    SyncQuality quality{SyncQuality::NoSignal};
    double latencyNowMs{0.0};
    double latencyAvgMs{0.0};
    double latencyMinMs{0.0};
    double latencyMaxMs{0.0};
    double latencyP95Ms{0.0};
    double jitterMs{0.0};
    double correctionMs{0.0};
    std::uint64_t sequenceGaps{0};
    std::uint64_t seekEvents{0};
};

class ReaperSyncSource final : public ISyncSource {
public:
    ReaperSyncSource();
    ~ReaperSyncSource() override;
    bool start() override;
    void stop() override;
    bool isConnected() const override;
    SyncState getState() const override;
    std::vector<Cue> markers() const;
    double packetAgeMs() const;
    std::uint64_t packetCount() const;
    PrecisionStats precisionStats() const;
private:
    void receiveLoop();
    mutable std::mutex mutex_;
    std::atomic<bool> running_{false};
    std::thread thread_;
    std::uintptr_t socket_{~std::uintptr_t{0}};
    SyncState state_{};
    std::vector<Cue> markers_;
    std::chrono::steady_clock::time_point lastPacket_{};
    std::chrono::steady_clock::time_point localAnchor_{};
    TimeNs remoteAnchorNs_{0};
    std::uint64_t packetCount_{0};
    std::uint64_t lastWireSequence_{0};
    bool haveSequence_{false};
    std::deque<double> latencySamples_;
    std::deque<double> intervalSamples_;
    double lastArrivalQpcMs_{0.0};
    double correctionMs_{0.0};
    std::uint64_t sequenceGaps_{0};
    std::uint64_t seekEvents_{0};
};
}
