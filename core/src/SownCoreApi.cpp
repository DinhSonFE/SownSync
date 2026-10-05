#include "sown/SownCoreApi.h"
#include "sown/CueEngine.hpp"
#include "sown/ReaperSyncSource.hpp"
#include "sown/SyncEngine.hpp"
#include "sown/SyncSourceManager.hpp"
#include <algorithm>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>

using namespace sown;
namespace {
std::mutex g;
std::shared_ptr<ReaperSyncSource> reaper;
std::shared_ptr<SyncSourceManager> manager;
std::unique_ptr<SyncEngine> engine;
CueEngine cues;
std::uint64_t lastPackets=0;
std::string projectCache,sourceCache;
void copy(char* d,size_t n,const std::string&s){if(!n)return;std::strncpy(d,s.c_str(),n-1);d[n-1]=0;}
void refresh(){if(!reaper)return;auto p=reaper->packetsReceived();if(p!=lastPackets){cues.setCues(reaper->markerCues());lastPackets=p;}}
void cueOut(SownCue*o,const Cue&c){o->id=c.id;o->time_ns=c.timeNs;o->warning_ns=c.warningNs;copy(o->department,sizeof(o->department),c.department);copy(o->name,sizeof(o->name),c.name);o->color=c.color;o->end_ns=c.endNs;o->is_region=c.isRegion?1:0;o->valid=1;}
}
extern "C" {
int sown_init(void){std::lock_guard<std::mutex>lk(g);if(engine)return 1;reaper=std::make_shared<ReaperSyncSource>(19101);if(!reaper->start()){reaper.reset();return 0;}manager=std::make_shared<SyncSourceManager>();manager->addSource("reaper","REAPER",reaper,SourceRole::Primary,10);engine=std::make_unique<SyncEngine>(manager);return 1;}
void sown_shutdown(void){std::lock_guard<std::mutex>lk(g);if(reaper)reaper->stop();engine.reset();manager.reset();reaper.reset();cues.setCues({});lastPackets=0;}
int sown_get_state(SownState*o){if(!o)return 0;std::lock_guard<std::mutex>lk(g);if(!engine)return 0;refresh();auto s=engine->state();o->connected=s.connected;o->locked=s.locked;o->transport=(int)s.transport;o->position_ns=s.positionNs;o->playback_rate=s.playbackRate;o->fps=s.fps;o->sequence=s.sequence;return 1;}
int sown_get_current_cue(SownCue*o){if(!o)return 0;std::lock_guard<std::mutex>lk(g);if(!engine)return 0;refresh();*o={};auto q=cues.evaluate(engine->state().positionNs);if(!q.current)return 1;cueOut(o,*q.current);return 1;}
int sown_get_next_cue(SownCue*o,int64_t*cd){if(!o)return 0;std::lock_guard<std::mutex>lk(g);if(!engine)return 0;refresh();*o={};auto q=cues.evaluate(engine->state().positionNs);if(cd)*cd=q.countdownNs;if(q.next)cueOut(o,*q.next);return 1;}
int sown_get_cue_count(void){std::lock_guard<std::mutex>lk(g);refresh();return (int)cues.cues().size();}
int sown_get_cue_at(int index,SownCue*o){if(!o||index<0)return 0;std::lock_guard<std::mutex>lk(g);refresh();*o={};const auto&v=cues.cues();if(static_cast<size_t>(index)>=v.size())return 0;cueOut(o,v[static_cast<size_t>(index)]);return 1;}
int sown_is_reaper_connected(void){std::lock_guard<std::mutex>lk(g);return reaper&&reaper->isConnected();}
const char* sown_get_project_name(void){std::lock_guard<std::mutex>lk(g);projectCache=reaper?reaper->projectName():"";return projectCache.c_str();}
const char* sown_get_active_source(void){std::lock_guard<std::mutex>lk(g);sourceCache=manager?manager->activeId():"";return sourceCache.c_str();}
double sown_get_reaper_tempo(void){std::lock_guard<std::mutex>lk(g);return reaper?reaper->tempo():0.0;}
int64_t sown_get_reaper_project_length_ns(void){std::lock_guard<std::mutex>lk(g);return reaper?reaper->projectLengthNs():0;}
int64_t sown_get_reaper_edit_cursor_ns(void){std::lock_guard<std::mutex>lk(g);return reaper?reaper->editCursorNs():0;}
uint32_t sown_get_reaper_project_revision(void){std::lock_guard<std::mutex>lk(g);return reaper?reaper->projectRevision():0;}
int sown_get_reaper_waveform(float*out,int capacity,int64_t*start_ns,int64_t*step_ns){std::lock_guard<std::mutex>lk(g);if(!reaper||!out||capacity<=0)return 0;auto p=reaper->waveformPeaks();const int n=std::min<int>(capacity,(int)p.size());for(int i=0;i<n;++i)out[i]=p[i];if(start_ns)*start_ns=reaper->waveformStartNs();if(step_ns)*step_ns=reaper->waveformStepNs();return n;}
const char* sown_version(void){return "0.7.1";}
}
