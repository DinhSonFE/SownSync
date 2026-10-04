#include "sown/CueEngine.hpp"
#include <algorithm>

namespace sown {
void CueEngine::setCues(std::vector<Cue> cues) {
    std::sort(cues.begin(), cues.end(), [](const Cue& a, const Cue& b){ return a.timeNs < b.timeNs; });
    cues_ = std::move(cues);
}
CueSnapshot CueEngine::evaluate(TimeNs position) const {
    CueSnapshot out;
    auto it = std::upper_bound(cues_.begin(), cues_.end(), position,
        [](TimeNs t, const Cue& cue){ return t < cue.timeNs; });
    if (it != cues_.begin()) out.current = *(it - 1);
    if (it != cues_.end()) { out.next = *it; out.countdownNs = std::max<TimeNs>(0, it->timeNs - position); }
    return out;
}
}
