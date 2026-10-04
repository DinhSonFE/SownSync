#include "sown/CueEngine.hpp"
#include "sown/Time.hpp"
#include <cassert>
#include <iostream>

int main() {
    using namespace sown;
    CueEngine e;
    e.setCues({{1, secondsToNs(5), "ALL", "A", 0}, {2, secondsToNs(10), "LIGHT", "B", 0}});
    assert(!e.currentCue(secondsToNs(1)));
    assert(e.nextCue(secondsToNs(1))->id == 1);
    assert(e.currentCue(secondsToNs(7))->id == 1);
    assert(e.nextCue(secondsToNs(7))->id == 2);
    assert(formatTime(secondsToNs(65.123)) == "00:01:05.123");
    std::cout << "Sown Core tests PASS\n";
}
