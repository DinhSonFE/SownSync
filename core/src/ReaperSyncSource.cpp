#include "sown/ReaperSyncSource.hpp"
#include "sown/Time.hpp"
#include <algorithm>
#include <cstring>
#include <cmath>
#include <numeric>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#pragma comment(lib, "Ws2_32.lib")
#endif
namespace sown {
#pragma pack(push,1)
struct WireHeader { char magic[4]; std::uint16_t version,type; std::uint32_t size; };
struct StatePacket { WireHeader h; std::uint64_t sequence; std::uint64_t senderQpc,senderQpcFreq; double positionSec,rate,fps; std::uint8_t transport,reserved[7]; char project[128]; };
struct MarkerPacket { WireHeader h; std::uint32_t generation,id; double positionSec; std::uint8_t isRegion,reserved[7]; char name[256]; };
struct MarkerBoundaryPacket { WireHeader h; std::uint32_t generation,count; };
#pragma pack(pop)
static bool validHeader(const WireHeader& h,int len){return std::memcmp(h.magic,"SOWN",4)==0&&h.version==3&&h.size<=static_cast<std::uint32_t>(len);}
ReaperSyncSource::ReaperSyncSource(unsigned short port):port_(port){state_.source=SyncSource::Reaper;state_.fps=25.0;latencyWindow_.reserve(512);} ReaperSyncSource::~ReaperSyncSource(){stop();}
bool ReaperSyncSource::start(){
#ifdef _WIN32
 if(running_)return true;WSADATA w{};if(WSAStartup(MAKEWORD(2,2),&w)!=0)return false;SOCKET s=::socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);if(s==INVALID_SOCKET){WSACleanup();return false;}sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons(port_);if(::bind(s,(sockaddr*)&a,sizeof(a))==SOCKET_ERROR){closesocket(s);WSACleanup();return false;}DWORD t=100;setsockopt(s,SOL_SOCKET,SO_RCVTIMEO,(const char*)&t,sizeof(t));socket_=(std::uintptr_t)s;running_=true;thread_=std::thread(&ReaperSyncSource::receiveLoop,this);return true;
#else
 return false;
#endif
}
void ReaperSyncSource::stop(){
#ifdef _WIN32
 if(!running_.exchange(false))return;if(socket_!=~std::uintptr_t{0}){closesocket((SOCKET)socket_);socket_=~std::uintptr_t{0};}if(thread_.joinable())thread_.join();WSACleanup();
#endif
 std::lock_guard l(mutex_);state_.connected=false;state_.locked=false;
}
bool ReaperSyncSource::isConnected()const{return getState().connected;}
SyncState ReaperSyncSource::getState()const{std::lock_guard l(mutex_);auto o=state_;auto now=Clock::now();bool fresh=lastPacket_!=Clock::time_point::min()&&now-lastPacket_<std::chrono::milliseconds(750);o.connected=fresh;o.locked=fresh;if(fresh&&o.transport==TransportState::Playing){double dt=std::chrono::duration<double>(now-anchorLocal_).count();o.positionNs=anchorPosition_+secondsToNs(dt*o.playbackRate);}else o.positionNs=anchorPosition_;return o;}
std::vector<Cue> ReaperSyncSource::markerCues()const{std::lock_guard l(mutex_);return markers_;}std::string ReaperSyncSource::projectName()const{std::lock_guard l(mutex_);return projectName_;}double ReaperSyncSource::packetAgeMs()const{std::lock_guard l(mutex_);if(lastPacket_==Clock::time_point::min())return -1;return std::chrono::duration<double,std::milli>(Clock::now()-lastPacket_).count();}PrecisionStats ReaperSyncSource::precisionStats()const{std::lock_guard l(mutex_);return precision_;}
void ReaperSyncSource::updatePrecision(std::uint64_t seq,std::uint64_t qpc,std::uint64_t freq,TimeNs pos,TransportState tr,Clock::time_point now){
 precision_.packets++;
 if(previousSequence_&&seq>previousSequence_+1)precision_.sequenceGaps+=seq-previousSequence_-1;
 if(previousArrival_!=Clock::time_point::min()){
  double interval=std::chrono::duration<double,std::milli>(now-previousArrival_).count();
  if(expectedIntervalMs_==0)expectedIntervalMs_=interval;else expectedIntervalMs_=expectedIntervalMs_*0.95+interval*0.05;
  double dev=std::abs(interval-expectedIntervalMs_);precision_.jitterMs=precision_.jitterMs*0.9+dev*0.1;
  if(previousTransport_==TransportState::Playing&&tr==TransportState::Playing){double elapsed=std::chrono::duration<double>(now-previousArrival_).count();TimeNs expected=previousPacketPosition_+secondsToNs(elapsed*state_.playbackRate);precision_.correctionMs=std::abs((double)(pos-expected))/1e6;if(precision_.correctionMs>150.0)precision_.seekEvents++;}
 }
#ifdef _WIN32
 LARGE_INTEGER rq{};QueryPerformanceCounter(&rq);if(qpc&&freq&&rq.QuadPart>=(LONGLONG)qpc){double latency=(double)(rq.QuadPart-(LONGLONG)qpc)*1000.0/(double)freq;precision_.latencyMs=latency;latencyWindow_.push_back(latency);if(latencyWindow_.size()>512)latencyWindow_.erase(latencyWindow_.begin());auto mm=std::minmax_element(latencyWindow_.begin(),latencyWindow_.end());precision_.latencyMinMs=*mm.first;precision_.latencyMaxMs=*mm.second;precision_.latencyAvgMs=std::accumulate(latencyWindow_.begin(),latencyWindow_.end(),0.0)/latencyWindow_.size();auto tmp=latencyWindow_;std::sort(tmp.begin(),tmp.end());precision_.latencyP95Ms=tmp[(std::size_t)std::floor((tmp.size()-1)*0.95)];}
#endif
 double score=precision_.latencyP95Ms+precision_.jitterMs*2.0;precision_.quality=score<5.0?"EXCELLENT":(score<15.0?"GOOD":(score<40.0?"FAIR":"UNSTABLE"));
 previousSequence_=seq;previousArrival_=now;previousPacketPosition_=pos;previousTransport_=tr;
}
void ReaperSyncSource::receiveLoop(){
#ifdef _WIN32
 char b[1024];while(running_){sockaddr_in f{};int fl=sizeof(f);int n=recvfrom((SOCKET)socket_,b,sizeof(b),0,(sockaddr*)&f,&fl);if(n>0){++packetsReceived_;handlePacket(b,n);}}
#endif
}
void ReaperSyncSource::handlePacket(const char*d,int len){if(len<(int)sizeof(WireHeader))return;auto&h=*(const WireHeader*)d;if(!validHeader(h,len))return;auto now=Clock::now();std::lock_guard l(mutex_);if(h.type==1&&len>=(int)sizeof(StatePacket)){auto&p=*(const StatePacket*)d;auto tr=p.transport==1?TransportState::Playing:(p.transport==2?TransportState::Paused:TransportState::Stopped);TimeNs pos=secondsToNs(std::max(0.0,p.positionSec));updatePrecision(p.sequence,p.senderQpc,p.senderQpcFreq,pos,tr,now);state_.source=SyncSource::Reaper;state_.sequence=p.sequence;state_.playbackRate=p.rate;state_.fps=p.fps>0?p.fps:25;state_.transport=tr;anchorPosition_=pos;anchorLocal_=now;lastPacket_=now;projectName_=std::string(p.project,std::char_traits<char>::length(p.project));}else if(h.type==2&&len>=(int)sizeof(MarkerBoundaryPacket)){auto&p=*(const MarkerBoundaryPacket*)d;markerGeneration_=p.generation;markerBuild_.clear();markerBuild_.reserve(p.count);}else if(h.type==3&&len>=(int)sizeof(MarkerPacket)){auto&p=*(const MarkerPacket*)d;if(p.generation!=markerGeneration_||p.isRegion)return;std::string raw(p.name,std::char_traits<char>::length(p.name)),dept="ALL",name=raw;if(auto x=raw.find('|');x!=std::string::npos){dept=raw.substr(0,x);name=raw.substr(x+1);}markerBuild_.push_back({p.id,secondsToNs(p.positionSec),dept,name,secondsToNs(5)});}else if(h.type==4&&len>=(int)sizeof(MarkerBoundaryPacket)){auto&p=*(const MarkerBoundaryPacket*)d;if(p.generation==markerGeneration_){std::sort(markerBuild_.begin(),markerBuild_.end(),[](auto&a,auto&b){return a.timeNs<b.timeNs;});markers_=markerBuild_;}}}
}
