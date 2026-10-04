#include "sown/CueEngine.hpp"
#include "sown/Time.hpp"
#include <cassert>
#include <iostream>
using namespace sown;
int main(){
    assert(secondsToNs(1.5)==1'500'000'000LL);
    CueEngine e; e.setCues({{1,secondsToNs(5),"A","ONE",0},{2,secondsToNs(10),"B","TWO",0},{3,secondsToNs(20),"C","THREE",0}});
    auto a=e.evaluate(secondsToNs(7)); assert(a.current && a.current->id==1); assert(a.next && a.next->id==2); assert(a.countdownNs==secondsToNs(3));
    auto b=e.evaluate(secondsToNs(15)); assert(b.current && b.current->id==2); assert(b.next && b.next->id==3);
    auto c=e.evaluate(secondsToNs(25)); assert(c.current && c.current->id==3); assert(!c.next);
    std::cout << "SownCoreTests PASS\n"; return 0;
}
