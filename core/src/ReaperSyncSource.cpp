#include "sown/ReaperSyncSource.hpp"
#include "sown/Time.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iomanip>
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
const char* toString(SyncHealth h){switch(h){case SyncHealth::NoSignal:return "NO SIGNAL";case SyncHealth::Locked:return "LOCKED";case SyncHealth::Holdover:return "HOLDOVER";case SyncHealth::Degraded:return "DEGRADED";case SyncHealth::Lost:return "LOST";}return "UNKNOWN";}
const char* toString(PhaseAcquisitionState s){switch(s){case PhaseAcquisitionState::Warmup:return "WARMUP";case PhaseAcquisitionState::Acquiring:return "ACQUIRING";case PhaseAcquisitionState::Stable:return "STABLE";case PhaseAcquisitionState::Locked:return "LOCKED";case PhaseAcquisitionState::Tracking:return "TRACKING";}return "UNKNOWN";}

ReaperSyncSource::ReaperSyncSource(unsigned short port):port_(port){state_.source=SyncSource::Reaper;state_.fps=25.0;latencyWindow_.reserve(512);phaseLearningWindow_.reserve(96);}
ReaperSyncSource::~ReaperSyncSource(){stop();}

void ReaperSyncSource::logPhaseSampleUnlocked(std::uint64_t sequence,std::uint64_t senderQpc,
 double senderDeltaMs,TimeNs positionNs,double positionDeltaMs,double rawPhaseMs,
 double baselineMs,double residualMs){
 if(!phaseLog_.is_open()){
  try{
   const auto dir=std::filesystem::current_path()/"logs";
   std::filesystem::create_directories(dir);
   phaseLogPath_=(dir/"phase_samples.csv").string();
   phaseLog_.open(phaseLogPath_,std::ios::out|std::ios::trunc);
  }catch(...){return;}
 }
 if(!phaseLog_)return;
 if(!phaseLogHeaderWritten_){
  phaseLog_<<"sequence,senderQpc,senderDeltaMs,positionNs,positionDeltaMs,rawPhaseMs,baselineMs,residualMs,state,phaseMadMs,stableWindows,phaseSamples\n";
  phaseLogHeaderWritten_=true;
 }
 phaseLog_<<sequence<<','<<senderQpc<<','<<std::fixed<<std::setprecision(6)
          <<senderDeltaMs<<','<<positionNs<<','<<positionDeltaMs<<','
          <<rawPhaseMs<<','<<baselineMs<<','<<residualMs<<','
          <<toString(phaseState_)<<','<<phaseMadMs_<<','
          <<phaseStableWindows_<<','<<phaseLockSamples_<<'\n';
 // Flush each sample intentionally: diagnostic logs must survive a crash/forced close.
 phaseLog_.flush();
}

void ReaperSyncSource::resetEstimatorUnlocked(){
 latencyWindow_.clear();
 expectedIntervalMs_=0.0;
 previousArrival_=Clock::time_point::min();
 previousPacketPosition_=0;
 previousSequence_=0;
 clockRateScale_=1.0;
 driftPpmFiltered_=0.0;
 precision_.latencyMs=precision_.latencyMinMs=precision_.latencyMaxMs=precision_.latencyAvgMs=precision_.latencyP95Ms=0.0;
 precision_.jitterMs=0.0;
 precision_.correctionMs=0.0;
 precision_.driftPpm=0.0;
 precision_.predictionErrorMs=0.0;
 precision_.packetRateHz=0.0;
 errorSquareEma_=0.0;
 sourceSlopeEma_=1.0;
 phaseBaselineMs_=0.0;
 residualSquareEma_=0.0;
 phaseLearningWindow_.clear();
 phaseState_=PhaseAcquisitionState::Warmup;
 phaseStableWindows_=0;
 phaseMadMs_=0.0;
 phaseLockSamples_=0;
 phaseLocked_=false;
 precision_.phaseBaselineMs=0.0;
 precision_.residualErrorMs=0.0;
 precision_.phaseLocked=false;
 precision_.phaseState=phaseState_;
 precision_.phaseMadMs=0.0;
 precision_.phaseStableWindows=0;
 precision_.phaseSamples=0;
 previousSenderQpc_=0;
 windowAnchorSenderQpc_=0;
 windowAnchorPosition_=0;
 windowPacketCount_=0;
 previousSenderQpcFreq_=0;
 precision_.windowPhaseMs=0.0;
 precision_.windowPackets=0;
 settlingPackets_=8;
 precision_.phaseErrorMs=0.0;
 precision_.errorRmsMs=0.0;
 precision_.errorPeakMs=0.0;
}

bool ReaperSyncSource::start(){
#ifdef _WIN32
 if(running_)return true;WSADATA w{};if(WSAStartup(MAKEWORD(2,2),&w)!=0)return false;SOCKET s=::socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);if(s==INVALID_SOCKET){WSACleanup();return false;}sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons(port_);if(::bind(s,(sockaddr*)&a,sizeof(a))==SOCKET_ERROR){closesocket(s);WSACleanup();return false;}DWORD t=100;setsockopt(s,SOL_SOCKET,SO_RCVTIMEO,(const char*)&t,sizeof(t));socket_=(std::uintptr_t)s;running_=true;thread_=std::thread(&ReaperSyncSource::receiveLoop,this);return true;
#else
 return false;
#endif
}
void ReaperSyncSource::stop(){
#ifdef _WIN32
 if(!running_.exchange(false)){if(phaseLog_.is_open())phaseLog_.close();return;}if(socket_!=~std::uintptr_t{0}){closesocket((SOCKET)socket_);socket_=~std::uintptr_t{0};}if(thread_.joinable())thread_.join();WSACleanup();
#endif
 if(phaseLog_.is_open())phaseLog_.close();std::lock_guard l(mutex_);state_.connected=false;state_.locked=false;precision_.health=SyncHealth::Lost;precision_.quality="NO SIGNAL";
}

void ReaperSyncSource::updateHealthUnlocked(Clock::time_point now) const {
 if(lastPacket_==Clock::time_point::min()){
  precision_.health=SyncHealth::NoSignal;precision_.quality="NO SIGNAL";
  precision_.clockMode="WAITING";precision_.packetAgeMs=-1;precision_.holdoverAgeMs=0.0;
  previousHealth_=SyncHealth::NoSignal;return;
 }
 const double age=std::chrono::duration<double,std::milli>(now-lastPacket_).count();
 precision_.packetAgeMs=age;
 SyncHealth next=SyncHealth::Locked;
 if(age>=750.0)next=SyncHealth::Lost;
 else if(age>=350.0)next=SyncHealth::Degraded;
 else if(age>=100.0)next=SyncHealth::Holdover;

 if(next!=previousHealth_){
  if(next==SyncHealth::Holdover){
   ++precision_.holdoverEntries;holdoverStarted_=now;
  }else if(next==SyncHealth::Degraded){
   ++precision_.degradedEntries;
   if(holdoverStarted_==Clock::time_point::min())holdoverStarted_=now;
  }else if(next==SyncHealth::Lost){
   ++precision_.lostEvents;
   if(holdoverStarted_==Clock::time_point::min())holdoverStarted_=now;
  }
  previousHealth_=next;
 }
 precision_.health=next;
 precision_.holdoverAgeMs=(next==SyncHealth::Holdover||next==SyncHealth::Degraded||next==SyncHealth::Lost)
  ?(holdoverStarted_==Clock::time_point::min()?age:std::chrono::duration<double,std::milli>(now-holdoverStarted_).count()):0.0;

 if(next==SyncHealth::Lost){
  precision_.quality="NO SIGNAL";precision_.clockMode="FROZEN";
  return;
 }
 if(next==SyncHealth::Holdover||next==SyncHealth::Degraded)precision_.clockMode="HOLDOVER";
 else precision_.clockMode="DISCIPLINED";
 const double score=precision_.latencyP95Ms+precision_.jitterMs*2.0+std::min(std::abs(precision_.driftPpm)/50.0,20.0);
 precision_.quality=score<5.0?"EXCELLENT":(score<15.0?"GOOD":(score<40.0?"FAIR":"UNSTABLE"));
}

TimeNs ReaperSyncSource::predictedPositionUnlocked(Clock::time_point now) const {
 if(state_.transport!=TransportState::Playing)return anchorPosition_;
 double dt=std::chrono::duration<double>(now-anchorLocal_).count();
 return std::max<TimeNs>(0,anchorPosition_+secondsToNs(dt*state_.playbackRate*clockRateScale_));
}

bool ReaperSyncSource::isConnected()const{return getState().connected;}
SyncState ReaperSyncSource::getState()const{
 std::lock_guard l(mutex_);auto now=Clock::now();updateHealthUnlocked(now);auto o=state_;
 o.connected=precision_.health!=SyncHealth::NoSignal&&precision_.health!=SyncHealth::Lost;
 o.locked=precision_.health==SyncHealth::Locked||precision_.health==SyncHealth::Holdover;
 if(o.connected)o.positionNs=predictedPositionUnlocked(now);
 else{
  o.positionNs=anchorPosition_;
  // V0.2.8.1: never expose stale PLAYING after the master source is LOST.
  if(precision_.health==SyncHealth::Lost)o.transport=TransportState::Stopped;
 }
 if(precision_.health==SyncHealth::Lost)wasLost_=true;
 return o;
}
std::vector<Cue> ReaperSyncSource::markerCues()const{std::lock_guard l(mutex_);return markers_;}
std::string ReaperSyncSource::projectName()const{std::lock_guard l(mutex_);return projectName_;}
double ReaperSyncSource::packetAgeMs()const{std::lock_guard l(mutex_);updateHealthUnlocked(Clock::now());return precision_.packetAgeMs;}
PrecisionStats ReaperSyncSource::precisionStats()const{std::lock_guard l(mutex_);auto now=Clock::now();updateHealthUnlocked(now);precision_.uptimeSec=std::chrono::duration<double>(now-startedAt_).count();return precision_;}

void ReaperSyncSource::updatePrecision(std::uint64_t seq,std::uint64_t qpc,std::uint64_t freq,TimeNs pos,TransportState tr,Clock::time_point now){
 precision_.packets++;
 if(previousSequence_){
  if(seq==previousSequence_){precision_.duplicatePackets++;return;}
  if(seq<previousSequence_){precision_.outOfOrderPackets++;return;}
  if(seq>previousSequence_+1)precision_.sequenceGaps+=seq-previousSequence_-1;
 }

 if(previousArrival_!=Clock::time_point::min()){
  const double arrivalSec=std::chrono::duration<double>(now-previousArrival_).count();
  const double arrivalMs=arrivalSec*1000.0;
  if(expectedIntervalMs_==0.0)expectedIntervalMs_=arrivalMs;
  else expectedIntervalMs_=expectedIntervalMs_*0.95+arrivalMs*0.05;
  precision_.packetRateHz=expectedIntervalMs_>0.0?1000.0/expectedIntervalMs_:0.0;
  precision_.jitterMs=precision_.jitterMs*0.9+std::abs(arrivalMs-expectedIntervalMs_)*0.1;

  double senderSec=0.0;
  const bool senderClockValid=qpc>previousSenderQpc_ && freq>0 && previousSenderQpc_>0 &&
      previousSenderQpcFreq_==freq;
  if(senderClockValid)senderSec=(double)(qpc-previousSenderQpc_)/(double)freq;

  if(previousTransport_==TransportState::Playing&&tr==TransportState::Playing&&senderClockValid&&senderSec>0.002){
   const double rate=state_.playbackRate>0.0?state_.playbackRate:1.0;
   const double timelineSec=(double)(pos-previousPacketPosition_)/1e9/rate;
   const double packetPhaseMs=(timelineSec-senderSec)*1000.0;

   // V0.2.6 Windowed Phase Estimator.
   // REAPER transport position is quantised by its audio/control sampling cadence.
   // Never discipline the clock from one packet delta. Measure phase over a
   // multi-packet sender-QPC window so the 23.22/46.44 ms quantisation cancels.
   constexpr int kWindowPackets=16;
   constexpr double kMaxWindowPhaseMs=50.0;
   if(windowAnchorSenderQpc_==0 || windowPacketCount_<=0){
    windowAnchorSenderQpc_=qpc;
    windowAnchorPosition_=pos;
    windowPacketCount_=1;
   }else{
    ++windowPacketCount_;
   }

   double windowPhaseMs=precision_.windowPhaseMs;
   double windowSenderSec=0.0;
   double windowTimelineSec=0.0;
   bool windowReady=false;
   if(windowPacketCount_>=kWindowPackets && qpc>windowAnchorSenderQpc_ && freq>0){
    windowSenderSec=(double)(qpc-windowAnchorSenderQpc_)/(double)freq;
    windowTimelineSec=(double)(pos-windowAnchorPosition_)/1e9/rate;
    if(windowSenderSec>0.1){
     windowPhaseMs=(windowTimelineSec-windowSenderSec)*1000.0;
     windowReady=std::abs(windowPhaseMs)<kMaxWindowPhaseMs;
    }
   }

   precision_.phaseErrorMs=packetPhaseMs;
   precision_.windowPhaseMs=windowPhaseMs;
   precision_.windowPackets=windowPacketCount_;

   if(settlingPackets_>0){
    phaseState_=PhaseAcquisitionState::Warmup;
   }else if(windowReady){
    // Each completed non-overlapping window is an independent low-noise phase sample.
    if(!phaseLocked_){
     phaseState_=PhaseAcquisitionState::Acquiring;
     phaseLearningWindow_.push_back(windowPhaseMs);
     if(phaseLearningWindow_.size()>32)phaseLearningWindow_.erase(phaseLearningWindow_.begin());
     phaseLockSamples_=(int)phaseLearningWindow_.size();

     // V0.2.7 Fast Phase Acquisition.
     // Acquisition and tracking use different confidence rules. Real REAPER
     // captures show a phase MAD around 4 ms, so the old fixed 3 ms gate could
     // remain ACQUIRING indefinitely even when the source was healthy.
     constexpr std::size_t kAcquireSamples=4;
     constexpr double kAcquireMadMs=8.0;
     constexpr double kAcquireCandidateStepMs=12.0;
     constexpr int kAcquireStableWindows=2;
     if(phaseLearningWindow_.size()>=kAcquireSamples){
      auto w=phaseLearningWindow_;
      std::sort(w.begin(),w.end());
      const double candidate=w[w.size()/2];
      std::vector<double> dev;dev.reserve(w.size());
      for(double v:w)dev.push_back(std::abs(v-candidate));
      std::sort(dev.begin(),dev.end());
      phaseMadMs_=dev[dev.size()/2];

      const bool baselineSeeded=phaseStableWindows_>0;
      const double candidateStep=baselineSeeded?std::abs(candidate-phaseBaselineMs_):0.0;
      const bool distributionGood=phaseMadMs_<=kAcquireMadMs;
      const bool candidateGood=!baselineSeeded||candidateStep<=kAcquireCandidateStepMs;

      if(distributionGood&&candidateGood){
       phaseState_=PhaseAcquisitionState::Stable;
       // During acquisition follow the robust median quickly. Once locked the
       // existing slow tracking rule below takes over.
       phaseBaselineMs_=baselineSeeded?(phaseBaselineMs_*0.35+candidate*0.65):candidate;
       ++phaseStableWindows_;
      }else{
       phaseState_=PhaseAcquisitionState::Acquiring;
       phaseStableWindows_=0;
      }

      if(phaseStableWindows_>=kAcquireStableWindows){
       phaseLocked_=true;
       phaseState_=PhaseAcquisitionState::Locked;
       phaseBaselineMs_=candidate;
       residualSquareEma_=0.0;
       precision_.errorRmsMs=0.0;
       precision_.errorPeakMs=0.0;
      }
     }
    }else{
     phaseState_=PhaseAcquisitionState::Tracking;
     const double delta=windowPhaseMs-phaseBaselineMs_;
     if(std::abs(delta)<std::max(6.0,phaseMadMs_*4.0))phaseBaselineMs_+=delta*0.02;
    }

    // Estimate long-term source frequency from the same quantisation-resistant window.
    if(windowSenderSec>0.1){
     const double sampleSlope=windowTimelineSec/windowSenderSec;
     if(std::abs(windowPhaseMs)<20.0){
      const double boundedSlope=std::clamp(sampleSlope,0.998,1.002);
      sourceSlopeEma_=sourceSlopeEma_*0.98+boundedSlope*0.02;
      driftPpmFiltered_=std::clamp((sourceSlopeEma_-1.0)*1e6,-2000.0,2000.0);
      precision_.driftPpm=driftPpmFiltered_;
      clockRateScale_=std::clamp(sourceSlopeEma_,0.998,1.002);
     }
    }
   }

   // V0.2.6.1: a window phase sample is valid only on the packet that
   // completes that window. Between completed windows keep the last published
   // residual; never subtract a new baseline from a stale windowPhaseMs.
   double residualMs=precision_.residualErrorMs;
   if(windowReady){
    residualMs=windowPhaseMs-phaseBaselineMs_;
    precision_.residualErrorMs=residualMs;
    precision_.predictionErrorMs=residualMs;
   }
   precision_.phaseBaselineMs=phaseBaselineMs_;
   precision_.phaseLocked=phaseLocked_;
   precision_.phaseState=phaseState_;
   precision_.phaseMadMs=phaseMadMs_;
   precision_.phaseStableWindows=phaseStableWindows_;
   precision_.phaseSamples=phaseLockSamples_;

   const double senderDeltaMs=senderSec*1000.0;
   const double positionDeltaMs=(double)(pos-previousPacketPosition_)/1e6;
   // CSV is still packet-by-packet for diagnostics. residualMs is the latest
   // completed-window residual, so it cannot run away between windows.
   logPhaseSampleUnlocked(seq,qpc,senderDeltaMs,pos,positionDeltaMs,
                          packetPhaseMs,phaseBaselineMs_,residualMs);

   const bool seek=std::abs(packetPhaseMs)>150.0;
   if(seek){
    precision_.seekEvents++;precision_.hardSnaps++;
    clockRateScale_=1.0;driftPpmFiltered_=0.0;sourceSlopeEma_=1.0;settlingPackets_=8;
    windowAnchorSenderQpc_=qpc;windowAnchorPosition_=pos;windowPacketCount_=1;
    phaseBaselineMs_=0.0;phaseLearningWindow_.clear();phaseState_=PhaseAcquisitionState::Warmup;phaseStableWindows_=0;phaseMadMs_=0.0;phaseLockSamples_=0;phaseLocked_=false;residualSquareEma_=0.0;
    precision_.phaseBaselineMs=0.0;precision_.residualErrorMs=0.0;precision_.phaseLocked=false;precision_.phaseState=PhaseAcquisitionState::Warmup;precision_.phaseMadMs=0.0;precision_.phaseStableWindows=0;precision_.phaseSamples=0;
    errorSquareEma_=0.0;precision_.errorRmsMs=0.0;precision_.errorPeakMs=0.0;
   }else if(settlingPackets_>0){
    --settlingPackets_;
    precision_.correctionMs=0.0;
   }else if(windowReady){
    residualSquareEma_=residualSquareEma_*0.90+(residualMs*residualMs)*0.10;
    precision_.errorRmsMs=std::sqrt(residualSquareEma_);
    precision_.errorPeakMs=std::max(precision_.errorPeakMs,std::abs(residualMs));
    precision_.correctionMs=std::abs(residualMs);
    if(phaseLocked_&&std::abs(residualMs)>1.0)precision_.softCorrections++;
   }

   if(windowReady){
    windowAnchorSenderQpc_=qpc;
    windowAnchorPosition_=pos;
    windowPacketCount_=1;
   }
  }else if(previousTransport_!=tr){
   settlingPackets_=8;
   windowAnchorSenderQpc_=0;windowAnchorPosition_=0;windowPacketCount_=0;
   phaseBaselineMs_=0.0;phaseLearningWindow_.clear();phaseState_=PhaseAcquisitionState::Warmup;phaseStableWindows_=0;phaseMadMs_=0.0;phaseLockSamples_=0;phaseLocked_=false;residualSquareEma_=0.0;
   precision_.phaseErrorMs=0.0;precision_.phaseBaselineMs=0.0;precision_.residualErrorMs=0.0;
   precision_.phaseLocked=false;precision_.predictionErrorMs=0.0;precision_.correctionMs=0.0;
  }
 }
#ifdef _WIN32
 LARGE_INTEGER rq{};QueryPerformanceCounter(&rq);
 if(qpc&&freq&&rq.QuadPart>=(LONGLONG)qpc){
  double latency=(double)(rq.QuadPart-(LONGLONG)qpc)*1000.0/(double)freq;
  precision_.latencyMs=latency;latencyWindow_.push_back(latency);
  if(latencyWindow_.size()>512)latencyWindow_.erase(latencyWindow_.begin());
  auto mm=std::minmax_element(latencyWindow_.begin(),latencyWindow_.end());
  precision_.latencyMinMs=*mm.first;precision_.latencyMaxMs=*mm.second;
  precision_.latencyAvgMs=std::accumulate(latencyWindow_.begin(),latencyWindow_.end(),0.0)/latencyWindow_.size();
  auto tmp=latencyWindow_;std::sort(tmp.begin(),tmp.end());
  precision_.latencyP95Ms=tmp[(std::size_t)std::floor((tmp.size()-1)*0.95)];
 }
#endif
 previousSequence_=seq;previousArrival_=now;previousPacketPosition_=pos;previousTransport_=tr;
 previousSenderQpc_=qpc;previousSenderQpcFreq_=freq;
}

void ReaperSyncSource::receiveLoop(){
#ifdef _WIN32
 char b[1024];while(running_){sockaddr_in f{};int fl=sizeof(f);int n=recvfrom((SOCKET)socket_,b,sizeof(b),0,(sockaddr*)&f,&fl);if(n>0){++packetsReceived_;handlePacket(b,n);}}
#endif
}

void ReaperSyncSource::handlePacket(const char*d,int len){
 if(len<(int)sizeof(WireHeader))return;auto&h=*(const WireHeader*)d;if(!validHeader(h,len))return;auto now=Clock::now();std::lock_guard l(mutex_);
 if(h.type==1&&len>=(int)sizeof(StatePacket)){
  auto&p=*(const StatePacket*)d;
  auto tr=p.transport==1?TransportState::Playing:(p.transport==2?TransportState::Paused:TransportState::Stopped);
  TimeNs pos=secondsToNs(std::max(0.0,p.positionSec));

  const double gapMs=lastPacket_==Clock::time_point::min()?0.0:
      std::chrono::duration<double,std::milli>(now-lastPacket_).count();
  const bool timedOut=gapMs>=750.0;
  const bool reconnect=everConnected_&&(wasLost_||timedOut);
  const bool shortRecovery=everConnected_&&!reconnect&&gapMs>=100.0;

  // Predict through a short packet outage using the last disciplined clock.
  // A sub-750 ms gap must not reset the estimator or snap the show timeline.
  const TimeNs predictedBeforeRecovery=predictedPositionUnlocked(now);
  const double recoveryErrMs=(double)(pos-predictedBeforeRecovery)/1e6;

  if(reconnect){
   ++precision_.reconnects;
   resetEstimatorUnlocked();
   anchorPosition_=pos;
   anchorLocal_=now;
   // First packet after a full reconnect is authoritative, including STOPPED.
   state_.transport=tr;
   previousTransport_=tr;
   wasLost_=false;
   previousHealth_=SyncHealth::Locked;
   holdoverStarted_=Clock::time_point::min();
   recoveringFromGap_=false;
  }else if(shortRecovery){
   ++precision_.holdoverRecoveries;
   precision_.lastRecoveryErrorMs=recoveryErrMs;
   previousHealth_=SyncHealth::Locked;
   holdoverStarted_=Clock::time_point::min();
   if(tr==TransportState::Playing){
    recoveringFromGap_=true;
   }else{
    // STOPPED/PAUSED from REAPER cancels holdover immediately. Do not slew
    // from the stale PLAYING prediction; snap the anchor to REAPER's position.
    recoveringFromGap_=false;
    anchorPosition_=pos;
    anchorLocal_=now;
    clockRateScale_=1.0;
    driftPpmFiltered_=0.0;
    sourceSlopeEma_=1.0;
    windowAnchorSenderQpc_=0;
    windowAnchorPosition_=0;
    windowPacketCount_=0;
    settlingPackets_=8;
   }
  }
  everConnected_=true;

  const bool authoritativeNonPlaying=(tr!=TransportState::Playing)&&(reconnect||shortRecovery);
  const TimeNs predicted=(reconnect||authoritativeNonPlaying)?pos:predictedBeforeRecovery;
  const double errMs=(reconnect||authoritativeNonPlaying)?0.0:recoveryErrMs;
  updatePrecision(p.sequence,p.senderQpc,p.senderQpcFreq,pos,tr,now);
  const bool discontinuity=(state_.transport==TransportState::Playing&&tr==TransportState::Playing&&std::abs(errMs)>150.0);
  const bool transportChanged=state_.transport!=tr;
  if(transportChanged){
   ++precision_.transportTransitions;
   if(tr==TransportState::Playing)++precision_.playTransitions;
   else if(tr==TransportState::Paused)++precision_.pauseTransitions;
   else ++precision_.stopTransitions;
  }
  if(discontinuity){
   anchorPosition_=pos;anchorLocal_=now;
   stoppedCandidatePackets_=0;
  }else if(transportChanged){
   // The first STOPPED/PAUSED packet is authoritative: freeze immediately.
   anchorPosition_=pos;anchorLocal_=now;
   stoppedCandidatePosition_=pos;stoppedCandidatePackets_=1;
   lastStoppedAnchor_=pos;
   recoveringFromGap_=false;
  }else if(tr==TransportState::Playing){
   double alpha=std::abs(errMs)<2.0?0.08:(std::abs(errMs)<20.0?0.25:0.65);
   if(recoveringFromGap_)alpha=std::min(alpha,0.12);
   anchorPosition_=predicted+static_cast<TimeNs>((double)(pos-predicted)*alpha);anchorLocal_=now;
   recoveringFromGap_=false;
   stoppedCandidatePackets_=0;
  }else{
   // V0.2.8.3: while STOPPED, never chase a continuously moving source value.
   // A real cursor seek becomes stable for consecutive packets, then is accepted.
   // secondsToNs() is a runtime helper, so MSVC cannot use it in constexpr.
   // 2 ms expressed directly in the core's nanosecond timebase.
   constexpr TimeNs kStoppedStableToleranceNs=2'000'000;
   constexpr int kStoppedStablePackets=3;
   if(std::llabs(pos-stoppedCandidatePosition_)<=kStoppedStableToleranceNs){
    ++stoppedCandidatePackets_;
   }else{
    stoppedCandidatePosition_=pos;
    stoppedCandidatePackets_=1;
   }
   if(stoppedCandidatePackets_==kStoppedStablePackets){
    // Accept one stable stopped-position change as a deliberate cursor seek.
    if(std::llabs(stoppedCandidatePosition_-lastStoppedAnchor_)>kStoppedStableToleranceNs){
     ++precision_.stoppedSeeks;
     lastStoppedAnchor_=stoppedCandidatePosition_;
    }
    anchorPosition_=stoppedCandidatePosition_;
    anchorLocal_=now;
   }
   recoveringFromGap_=false;
  }
  state_.source=SyncSource::Reaper;state_.sequence=p.sequence;state_.playbackRate=p.rate;state_.fps=p.fps>0?p.fps:25;state_.transport=tr;lastPacket_=now;projectName_=std::string(p.project,std::char_traits<char>::length(p.project));updateHealthUnlocked(now);
 }else if(h.type==2&&len>=(int)sizeof(MarkerBoundaryPacket)){auto&p=*(const MarkerBoundaryPacket*)d;markerGeneration_=p.generation;markerBuild_.clear();markerBuild_.reserve(p.count);}
 else if(h.type==3&&len>=(int)sizeof(MarkerPacket)){auto&p=*(const MarkerPacket*)d;if(p.generation!=markerGeneration_||p.isRegion)return;std::string raw(p.name,std::char_traits<char>::length(p.name)),dept="ALL",name=raw;if(auto x=raw.find('|');x!=std::string::npos){dept=raw.substr(0,x);name=raw.substr(x+1);}markerBuild_.push_back({p.id,secondsToNs(p.positionSec),dept,name,secondsToNs(5)});}
 else if(h.type==4&&len>=(int)sizeof(MarkerBoundaryPacket)){auto&p=*(const MarkerBoundaryPacket*)d;if(p.generation==markerGeneration_){std::sort(markerBuild_.begin(),markerBuild_.end(),[](auto&a,auto&b){return a.timeNs<b.timeNs;});markers_=markerBuild_;}}
}
}
