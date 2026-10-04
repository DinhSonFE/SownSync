#pragma once
#include "Time.hpp"
#include <cstdint>
#include <string>

namespace sown {
struct Cue {
    std::uint32_t id{0};
    TimeNs timeNs{0};
    std::string department{"ALL"};
    std::string name;
    TimeNs warningNs{0};
};
}
