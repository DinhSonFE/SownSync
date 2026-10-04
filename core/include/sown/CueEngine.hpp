#pragma once
#include "Cue.hpp"
#include <optional>
#include <vector>

namespace sown {
struct CueSnapshot {
    std::optional<Cue> current;
    std::optional<Cue> next;
    TimeNs countdownNs{0};
};

class CueEngine {
public:
    void setCues(std::vector<Cue> cues);
    const std::vector<Cue>& cues() const { return cues_; }
    CueSnapshot evaluate(TimeNs position) const;
private:
    std::vector<Cue> cues_;
};
}
