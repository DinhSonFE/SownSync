#pragma once
#include "Cue.hpp"
#include <optional>
#include <vector>

namespace sown {
class CueEngine {
public:
    void setCues(std::vector<Cue> cues);
    const std::vector<Cue>& cues() const;
    std::optional<Cue> currentCue(TimeNs position) const;
    std::optional<Cue> nextCue(TimeNs position) const;
private:
    std::vector<Cue> cues_;
};
}
