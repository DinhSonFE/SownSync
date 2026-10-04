#include "sown/InternalSyncSource.hpp"
#include <algorithm>

namespace sown {
TimeNs InternalSyncSource::positionUnlocked(Clock::time_point now) const {
    if (transport_ != TransportState::Playing) return basePosition_;
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(now - anchor_).count();
    return std::max<TimeNs>(0, basePosition_ + elapsed);
}
bool InternalSyncSource::start() { std::scoped_lock lock(mutex_); connected_=true; anchor_=Clock::now(); ++sequence_; return true; }
void InternalSyncSource::stop() { std::scoped_lock lock(mutex_); basePosition_=positionUnlocked(Clock::now()); transport_=TransportState::Stopped; connected_=false; ++sequence_; }
bool InternalSyncSource::isConnected() const { std::scoped_lock lock(mutex_); return connected_; }
SyncState InternalSyncSource::getState() const {
    std::scoped_lock lock(mutex_);
    SyncState s; s.source=SyncSource::Internal; s.connected=connected_; s.locked=connected_; s.transport=transport_; s.positionNs=positionUnlocked(Clock::now()); s.sequence=sequence_; return s;
}
void InternalSyncSource::play() { std::scoped_lock lock(mutex_); if (transport_==TransportState::Playing) return; anchor_=Clock::now(); transport_=TransportState::Playing; ++sequence_; }
void InternalSyncSource::pause() { std::scoped_lock lock(mutex_); if (transport_!=TransportState::Playing) return; basePosition_=positionUnlocked(Clock::now()); transport_=TransportState::Paused; ++sequence_; }
void InternalSyncSource::seek(TimeNs p) { std::scoped_lock lock(mutex_); basePosition_=std::max<TimeNs>(0,p); anchor_=Clock::now(); ++sequence_; }
void InternalSyncSource::reset() { seek(0); }
}
