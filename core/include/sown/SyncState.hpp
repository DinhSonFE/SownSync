#pragma once
#include "Time.hpp"
#include <cstdint>
#include <string>

namespace sown {
enum class TransportState { Stopped, Playing, Paused };
enum class SyncSource { Internal, Reaper, CuePoints, LTC, MTC };

struct SyncState {
    SyncSource source{SyncSource::Internal};
    bool connected{false};
    bool locked{false};
    TransportState transport{TransportState::Stopped};
    TimeNs positionNs{0};
    double playbackRate{1.0};
    double fps{30.0};
    std::uint64_t sequence{0};
    std::string projectName;
};
}
