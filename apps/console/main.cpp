#include "sown/CueEngine.hpp"
#include "sown/ReaperSyncSource.hpp"
#include "sown/SyncEngine.hpp"
#include "sown/Time.hpp"
#include <chrono>
#include <cctype>
#include <iostream>
#include <memory>
#include <optional>
#include <thread>
#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#endif
using namespace sown; using Clock=std::chrono::steady_clock;
static void clearConsole(){
#ifdef _WIN32
HANDLE out=GetStdHandle(STD_OUTPUT_HANDLE);CONSOLE_SCREEN_BUFFER_INFO i{};if(out!=INVALID_HANDLE_VALUE&&GetConsoleScreenBufferInfo(out,&i)){DWORD n=0;COORD h{0,0};DWORD cells=(DWORD)i.dwSize.X*i.dwSize.Y;FillConsoleOutputCharacterA(out,' ',cells,h,&n);FillConsoleOutputAttribute(out,i.wAttributes,cells,h,&n);SetConsoleCursorPosition(out,h);return;}
#endif
std::cout<<"\x1B[2J\x1B[H";}
static void printCue(const char*l,const std::optional<Cue>&c){std::cout<<l<<"\n";if(!c){std::cout<<"  --\n";return;}std::cout<<"  ["<<c->id<<"] "<<c->department<<" | "<<c->name<<" @ "<<formatDuration(c->timeNs)<<"\n";}
static std::optional<char> key(){
#ifdef _WIN32
if(_kbhit())return(char)_getch();
#endif
return std::nullopt;}
int main(){
#ifdef _WIN32
SetConsoleOutputCP(CP_UTF8);
#endif
auto reaper=std::make_shared<ReaperSyncSource>(19101);if(!reaper->start()){std::cerr<<"Failed to start REAPER UDP adapter on 127.0.0.1:19101\n";return 1;}SyncEngine sync(reaper);CueEngine cues;std::uint64_t lastMarkerPackets=0;constexpr auto tickPeriod=std::chrono::milliseconds(1),renderPeriod=std::chrono::milliseconds(100);auto next=Clock::now(),render=next,perf=next;std::uint64_t ticks=0,renders=0;double hz=0,fps=0,maxTick=0;bool quit=false;
while(!quit){auto ts=Clock::now();if(auto k=key()){char c=(char)std::tolower((unsigned char)*k);if(c=='q')quit=true;}auto st=sync.state();auto pc=reaper->packetsReceived();if(pc!=lastMarkerPackets){cues.setCues(reaper->markerCues());lastMarkerPackets=pc;}auto snap=cues.evaluate(st.positionNs);++ticks;auto now=Clock::now();if(now>=render){clearConsole();std::cout<<"SOWN SYNC CORE v0.2.3 - SYNC ENGINE STABILITY\n====================================\n";std::cout<<"SOURCE       REAPER\nSTATUS       "<<(st.locked?"LOCKED":"WAITING FOR BRIDGE")<<"\nTRANSPORT    "<<toString(st.transport)<<"\nPOSITION     "<<formatDuration(st.positionNs)<<"\nPROJECT      "<<(reaper->projectName().empty()?"--":reaper->projectName())<<"\nPACKETS      "<<pc<<"\nPACKET AGE   "<<reaper->packetAgeMs()<<" ms\nMARKERS      "<<cues.cues().size()<<"\n\n";printCue("CURRENT CUE",snap.current);printCue("NEXT CUE",snap.next);if(snap.next)std::cout<<"COUNTDOWN    "<<formatDuration(snap.countdownNs)<<"\n";auto ps=reaper->precisionStats();std::cout<<"\nCLOCK / SYNC HEALTH\n  Health        "<<toString(ps.health)<<"\n  Clock mode    "<<ps.clockMode<<"\n  Quality       "<<ps.quality<<"\n  Packet rate   "<<ps.packetRateHz<<" Hz\n  Packet age    "<<ps.packetAgeMs<<" ms\n  Latency now   "<<ps.latencyMs<<" ms\n  Latency avg   "<<ps.latencyAvgMs<<" ms\n  Latency P95   "<<ps.latencyP95Ms<<" ms\n  Jitter        "<<ps.jitterMs<<" ms\n  Pred error    "<<ps.predictionErrorMs<<" ms\n  Drift         "<<ps.driftPpm<<" ppm\n  Correction    "<<ps.correctionMs<<" ms\n  Seq gaps      "<<ps.sequenceGaps<<"\n  Seek events   "<<ps.seekEvents<<"\n  Hard snaps    "<<ps.hardSnaps<<"\n  Soft corr     "<<ps.softCorrections<<"\n  Reconnects    "<<ps.reconnects<<"\n  Duplicates    "<<ps.duplicatePackets<<"\n  Out of order  "<<ps.outOfOrderPackets<<"\n  Error RMS     "<<ps.errorRmsMs<<" ms\n  Error peak    "<<ps.errorPeakMs<<" ms\n  Uptime        "<<ps.uptimeSec<<" sec\n\nPERFORMANCE\n  Core rate     "<<(int)(hz+.5)<<" Hz\n  Console rate  "<<(int)(fps+.5)<<" FPS\n  Max tick      "<<maxTick<<" ms\n\n[q] Quit\n";if(!st.connected){if(pc==0)std::cout<<"\nNo REAPER bridge detected. Install/check reaper_sown_bridge.dll in REAPER/UserPlugins.\n";else std::cout<<"\nREAPER connection lost - waiting for automatic reconnect.\n";}std::cout.flush();++renders;render=now+renderPeriod;}auto end=Clock::now();double ms=std::chrono::duration<double,std::milli>(end-ts).count();if(ms>maxTick)maxTick=ms;double elapsed=std::chrono::duration<double>(end-perf).count();if(elapsed>=1){hz=ticks/elapsed;fps=renders/elapsed;ticks=renders=0;maxTick=0;perf=end;}next+=tickPeriod;if(next>Clock::now())std::this_thread::sleep_until(next);else if(Clock::now()-next>std::chrono::milliseconds(100))next=Clock::now();}
reaper->stop();clearConsole();std::cout<<"SOWN SYNC CORE v0.2.3 stopped.\n";}
