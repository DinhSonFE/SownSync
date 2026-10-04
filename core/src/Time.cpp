#include "sown/Time.hpp"
#include "sown/SyncState.hpp"
#include <cmath>
#include <iomanip>
#include <sstream>

namespace sown {
TimeNs secondsToNs(double seconds) { return static_cast<TimeNs>(std::llround(seconds * kNsPerSecond)); }
double nsToSeconds(TimeNs ns) { return static_cast<double>(ns) / static_cast<double>(kNsPerSecond); }
std::string formatDuration(TimeNs ns, bool milliseconds) {
    if (ns < 0) ns = 0;
    auto totalMs = ns / kNsPerMillisecond;
    auto ms = totalMs % 1000;
    auto totalSec = totalMs / 1000;
    auto sec = totalSec % 60;
    auto min = (totalSec / 60) % 60;
    auto hour = totalSec / 3600;
    std::ostringstream os;
    os << std::setfill('0') << std::setw(2) << hour << ':' << std::setw(2) << min << ':' << std::setw(2) << sec;
    if (milliseconds) os << '.' << std::setw(3) << ms;
    return os.str();
}
const char* toString(TransportState s) {
    switch (s) { case TransportState::Stopped:return "STOPPED"; case TransportState::Playing:return "PLAYING"; case TransportState::Paused:return "PAUSED"; }
    return "UNKNOWN";
}
const char* toString(SyncSource s) {
    switch (s) { case SyncSource::Internal:return "INTERNAL"; case SyncSource::Reaper:return "REAPER"; case SyncSource::CuePoints:return "CUEPOINTS"; case SyncSource::LTC:return "LTC"; case SyncSource::MTC:return "MTC"; case SyncSource::ArtNet:return "ART-NET"; }
    return "UNKNOWN";
}
}
