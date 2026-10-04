#include "sown/Time.hpp"
#include <algorithm>
#include <iomanip>
#include <sstream>

namespace sown {
TimeNs secondsToNs(double s) { return static_cast<TimeNs>(s * static_cast<double>(kNsPerSecond)); }
double nsToSeconds(TimeNs ns) { return static_cast<double>(ns) / static_cast<double>(kNsPerSecond); }
std::string formatTime(TimeNs ns) {
    ns = std::max<TimeNs>(0, ns);
    const auto totalMs = ns / 1'000'000;
    const auto ms = totalMs % 1000;
    const auto totalSec = totalMs / 1000;
    const auto sec = totalSec % 60;
    const auto totalMin = totalSec / 60;
    const auto min = totalMin % 60;
    const auto hour = totalMin / 60;
    std::ostringstream out;
    out << std::setfill('0') << std::setw(2) << hour << ":" << std::setw(2) << min << ":"
        << std::setw(2) << sec << "." << std::setw(3) << ms;
    return out.str();
}
}
