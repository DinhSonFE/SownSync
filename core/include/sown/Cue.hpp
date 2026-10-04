#pragma once
#include "Time.hpp"
#include <cstdint>
#include <string>

namespace sown {
struct Cue {
    std::uint32_t id{};
    TimeNs timeNs{};
    std::string department;
    std::string name;
    TimeNs warningNs{5 * kNsPerSecond};
};
}
