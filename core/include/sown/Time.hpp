#pragma once
#include <cstdint>
#include <string>

namespace sown {
using TimeNs = std::int64_t;
constexpr TimeNs kNsPerSecond = 1'000'000'000LL;
TimeNs secondsToNs(double seconds);
double nsToSeconds(TimeNs ns);
std::string formatTime(TimeNs ns);
}
