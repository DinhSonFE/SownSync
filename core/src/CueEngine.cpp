#include "sown/CueEngine.hpp"
#include <algorithm>

namespace sown {
void CueEngine::setCues(std::vector<Cue> cues) {
    std::sort(cues.begin(), cues.end(), [](const Cue& a, const Cue& b) { return a.timeNs < b.timeNs; });
    cues_ = std::move(cues);
}
const std::vector<Cue>& CueEngine::cues() const { return cues_; }
std::optional<Cue> CueEngine::currentCue(TimeNs p) const {
    auto it = std::upper_bound(cues_.begin(), cues_.end(), p, [](TimeNs v, const Cue& c) { return v < c.timeNs; });
    if (it == cues_.begin()) return std::nullopt;
    return *std::prev(it);
}
std::optional<Cue> CueEngine::nextCue(TimeNs p) const {
    auto it = std::upper_bound(cues_.begin(), cues_.end(), p, [](TimeNs v, const Cue& c) { return v < c.timeNs; });
    if (it == cues_.end()) return std::nullopt;
    return *it;
}
}
