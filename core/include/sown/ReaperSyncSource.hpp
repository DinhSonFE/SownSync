#pragma once
#include "ISyncSource.hpp"
#include "Cue.hpp"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace sown {
enum class SyncHealth { NoSignal, Locked, Holdover, Degraded, Lost };
enum class PhaseAcquisitionState { Warmup, Acquiring, Stable, Locked, Tracking };
const char* toString(PhaseAcquisitionState state);
const char* toString(SyncHealth health);

struct PrecisionStats {
    double latencyMs{0.0}, latencyMinMs{0.0}, latencyMaxMs{0.0}, latencyAvgMs{0.0}, latencyP95Ms{0.0};
    double jitterMs{0.0};
    double correctionMs{0.0};
    double driftPpm{0.0};
    double predictionErrorMs{0.0};
    double packetRateHz{0.0};
    double packetAgeMs{0.0};
    double phaseErrorMs{0.0};
    double phaseBaselineMs{0.0};
    double residualErrorMs{0.0};
    bool phaseLocked{false};
    PhaseAcquisitionState phaseState{PhaseAcquisitionState::Warmup};
    double phaseMadMs{0.0};
    int phaseStableWindows{0};
    int phaseSamples{0};
    double errorRmsMs{0.0};
    double errorPeakMs{0.0};
    double uptimeSec{0.0};
    std::uint64_t packets{0}, sequenceGaps{0}, seekEvents{0}, hardSnaps{0}, softCorrections{0}, reconnects{0}, duplicatePackets{0}, outOfOrderPackets{0};
    SyncHealth health{SyncHealth::NoSignal};
    const char* quality{"NO SIGNAL"};
    const char* clockMode{"WAITING"};
};

class ReaperSyncSource final : public ISyncSource {
public:
    explicit ReaperSyncSource(unsigned short port = 19101);
    ~ReaperSyncSource() override;
    bool start() override;
    void stop() override;
    bool isConnected() const override;
    SyncState getState() const override;
    std::vector<Cue> markerCues() const;
    std::string projectName() const;
    double packetAgeMs() const;
    PrecisionStats precisionStats() const;
    std::uint64_t packetsReceived() const { return packetsReceived_.load(); }
private:
    using Clock = std::chrono::steady_clock;
    void receiveLoop();
    void handlePacket(const char* data, int len);
    void updatePrecision(std::uint64_t sequence, std::uint64_t senderQpc, std::uint64_t senderQpcFreq,
                         TimeNs newPosition, TransportState newTransport, Clock::time_point now);
    void updateHealthUnlocked(Clock::time_point now) const;
    TimeNs predictedPositionUnlocked(Clock::time_point now) const;
    void resetEstimatorUnlocked();
    void logPhaseSampleUnlocked(std::uint64_t sequence, std::uint64_t senderQpc,
                                double senderDeltaMs, TimeNs positionNs,
                                double positionDeltaMs, double rawPhaseMs,
                                double baselineMs, double residualMs);
    unsigned short port_;
    std::atomic<bool> running_{false};
    std::thread thread_;
    mutable std::mutex mutex_;
    SyncState state_{};
    TimeNs anchorPosition_{0};
    Clock::time_point anchorLocal_{Clock::now()};
    Clock::time_point lastPacket_{Clock::time_point::min()};
    Clock::time_point previousArrival_{Clock::time_point::min()};
    TimeNs previousPacketPosition_{0};
    TransportState previousTransport_{TransportState::Stopped};
    std::uint64_t previousSequence_{0};
    std::vector<double> latencyWindow_;
    double expectedIntervalMs_{0.0};
    mutable PrecisionStats precision_{};
    double clockRateScale_{1.0};
    double driftPpmFiltered_{0.0};
    double errorSquareEma_{0.0};
    double sourceSlopeEma_{1.0};
    double phaseBaselineMs_{0.0};
    double residualSquareEma_{0.0};
    std::vector<double> phaseLearningWindow_;
    PhaseAcquisitionState phaseState_{PhaseAcquisitionState::Warmup};
    int phaseStableWindows_{0};
    double phaseMadMs_{0.0};
    int phaseLockSamples_{0};
    bool phaseLocked_{false};
    std::uint64_t previousSenderQpc_{0};
    std::uint64_t previousSenderQpcFreq_{0};
    int settlingPackets_{0};
    Clock::time_point startedAt_{Clock::now()};
    bool everConnected_{false};
    mutable bool wasLost_{false};
    std::vector<Cue> markers_, markerBuild_;
    std::uint32_t markerGeneration_{0};
    std::string projectName_;
    std::atomic<std::uint64_t> packetsReceived_{0};
    std::ofstream phaseLog_;
    std::string phaseLogPath_;
    bool phaseLogHeaderWritten_{false};
#ifdef _WIN32
    std::uintptr_t socket_{~std::uintptr_t{0}};
#endif
};
}
