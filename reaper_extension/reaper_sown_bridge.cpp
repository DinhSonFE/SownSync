// SOWN REAPER Bridge v0.2 - Windows x64 REAPER extension.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <cstdint>
#include <cstring>
#include <cstdio>

#define REAPER_PLUGIN_VERSION 0x20E
#define REAPER_PLUGIN_DLL_EXPORT __declspec(dllexport)
struct reaper_plugin_info_t { int caller_version; HWND hwnd_main; int (*Register)(const char*,void*); void* (*GetFunc)(const char*); };
struct ReaProject;

using GetPlayPositionEx_t=double(*)(ReaProject*);
using GetPlayPosition2Ex_t=double(*)(ReaProject*);
using GetPlayStateEx_t=int(*)(ReaProject*);
using GetCursorPositionEx_t=double(*)(ReaProject*);
using EnumProjects_t=ReaProject*(*)(int,char*,int);
using EnumProjectMarkers3_t=int(*)(ReaProject*,int,bool*,double*,double*,const char**,int*,int*);
using CountProjectMarkers_t=int(*)(ReaProject*,int*,int*);
using GetProjectName_t=void(*)(ReaProject*,char*,int);
using GetSetProjectInfo_t=double(*)(ReaProject*,const char*,double,bool);
using GetProjectStateChangeCount_t=int(*)(ReaProject*);
using GetPlayRate_t=double(*)(ReaProject*);
using Master_GetTempo_t=double(*)();
using GetProjectLength_t=double(*)(ReaProject*);

static reaper_plugin_info_t* g_rec{}; static SOCKET g_sock=INVALID_SOCKET; static sockaddr_in g_dest{}; static std::uint64_t g_seq=0; static std::uint32_t g_generation=0; static int g_lastChange=-1; static ULONGLONG g_lastMarkers=0;
static GetPlayPositionEx_t pGetPlayPositionEx{}; static GetPlayPosition2Ex_t pGetPlayPosition2Ex{}; static GetPlayStateEx_t pGetPlayStateEx{}; static GetCursorPositionEx_t pGetCursorPositionEx{}; static EnumProjects_t pEnumProjects{}; static EnumProjectMarkers3_t pEnumProjectMarkers3{}; static CountProjectMarkers_t pCountProjectMarkers{}; static GetProjectName_t pGetProjectName{}; static GetSetProjectInfo_t pGetSetProjectInfo{}; static GetProjectStateChangeCount_t pGetProjectStateChangeCount{}; static GetPlayRate_t pGetPlayRate{}; static Master_GetTempo_t pMaster_GetTempo{}; static GetProjectLength_t pGetProjectLength{};
#pragma pack(push,1)
struct H{char magic[4];std::uint16_t version,type;std::uint32_t size;};
struct State{H h;std::uint64_t sequence;std::uint64_t senderQpc,senderQpcFreq;double positionSec,rate,fps;std::uint8_t transport,reserved[7];char project[128];};
struct ProjectState{H h;std::uint64_t sequence;double cursorSec,lengthSec,tempo;std::uint32_t stateChangeCount;std::uint8_t transport,reserved[3];};
struct Marker{H h;std::uint32_t generation,id;double positionSec,endSec;std::uint32_t color;std::uint8_t isRegion,reserved[3];char name[256];};
struct Boundary{H h;std::uint32_t generation,count;};
#pragma pack(pop)
static H header(std::uint16_t t,std::uint32_t s){H h{{'S','O','W','N'},4,t,s};return h;}
static void sendRaw(const void* p,int n){ if(g_sock!=INVALID_SOCKET) sendto(g_sock,(const char*)p,n,0,(sockaddr*)&g_dest,sizeof(g_dest)); }
static void sendMarkers(ReaProject* proj){ int nm=0,nr=0; pCountProjectMarkers(proj,&nm,&nr); const std::uint32_t gen=++g_generation; Boundary b{header(2,sizeof(Boundary)),gen,(std::uint32_t)(nm+nr)};sendRaw(&b,sizeof(b)); for(int i=0;;++i){bool isr=false;double pos=0,end=0;const char* name="";int id=0,color=0;if(!pEnumProjectMarkers3(proj,i,&isr,&pos,&end,&name,&id,&color))break;Marker m{};m.h=header(3,sizeof(Marker));m.generation=gen;m.id=(std::uint32_t)id;m.positionSec=pos;m.endSec=end;m.color=(std::uint32_t)color;m.isRegion=isr?1:0;strncpy_s(m.name,name?name:"",_TRUNCATE);sendRaw(&m,sizeof(m));} b.h=header(4,sizeof(Boundary));sendRaw(&b,sizeof(b)); }
static void timer(){
 if(!pEnumProjects)return;
 ReaProject* proj=pEnumProjects(-1,nullptr,0);
 if(!proj)return;

 State s{};
 s.h=header(1,sizeof(State));
 s.sequence=++g_seq;

 LARGE_INTEGER q{},qf{};
 QueryPerformanceCounter(&q);
 QueryPerformanceFrequency(&qf);
 s.senderQpc=(std::uint64_t)q.QuadPart;
 s.senderQpcFreq=(std::uint64_t)qf.QuadPart;

 const int ps=pGetPlayStateEx(proj);
 s.transport=(ps&1)?1:((ps&2)?2:0);
 const bool activelyPlaying=(ps&1)!=0;

 // PLAYING uses REAPER's playback clock. STOPPED/PAUSED uses the edit cursor,
 // which is authoritative and does not keep advancing after transport stops.
 if(activelyPlaying){
  s.positionSec=pGetPlayPosition2Ex?pGetPlayPosition2Ex(proj):pGetPlayPositionEx(proj);
 }else{
  s.positionSec=pGetCursorPositionEx
      ?pGetCursorPositionEx(proj)
      :(pGetPlayPosition2Ex?pGetPlayPosition2Ex(proj):pGetPlayPositionEx(proj));
 }

 s.rate=pGetPlayRate?pGetPlayRate(proj):1.0;
 s.fps=pGetSetProjectInfo?pGetSetProjectInfo(proj,"PROJECT_FRAMERATE",0.0,false):25.0;
 if(s.fps<=0.0)s.fps=25.0;
 pGetProjectName(proj,s.project,sizeof(s.project));
 sendRaw(&s,sizeof(s));
 ProjectState psx{};psx.h=header(5,sizeof(ProjectState));psx.sequence=s.sequence;psx.cursorSec=pGetCursorPositionEx?pGetCursorPositionEx(proj):s.positionSec;psx.lengthSec=pGetProjectLength?pGetProjectLength(proj):0.0;psx.tempo=pMaster_GetTempo?pMaster_GetTempo():120.0;psx.stateChangeCount=(std::uint32_t)(pGetProjectStateChangeCount?pGetProjectStateChangeCount(proj):0);psx.transport=s.transport;sendRaw(&psx,sizeof(psx));

 const int ch=pGetProjectStateChangeCount?pGetProjectStateChangeCount(proj):0;
 const auto now=GetTickCount64();
 if(ch!=g_lastChange||now-g_lastMarkers>1000){
  g_lastChange=ch;
  g_lastMarkers=now;
  sendMarkers(proj);
 }
}
extern "C" REAPER_PLUGIN_DLL_EXPORT int ReaperPluginEntry(HINSTANCE,reaper_plugin_info_t* rec){ if(!rec){if(g_rec)g_rec->Register("-timer",(void*)timer);if(g_sock!=INVALID_SOCKET)closesocket(g_sock);WSACleanup();g_rec=nullptr;return 0;}if(rec->caller_version!=REAPER_PLUGIN_VERSION)return 0;g_rec=rec;auto F=[&](const char*n){return rec->GetFunc(n);};pGetPlayPositionEx=(GetPlayPositionEx_t)F("GetPlayPositionEx");pGetPlayPosition2Ex=(GetPlayPosition2Ex_t)F("GetPlayPosition2Ex");pGetPlayStateEx=(GetPlayStateEx_t)F("GetPlayStateEx");pGetCursorPositionEx=(GetCursorPositionEx_t)F("GetCursorPositionEx");pEnumProjects=(EnumProjects_t)F("EnumProjects");pEnumProjectMarkers3=(EnumProjectMarkers3_t)F("EnumProjectMarkers3");pCountProjectMarkers=(CountProjectMarkers_t)F("CountProjectMarkers");pGetProjectName=(GetProjectName_t)F("GetProjectName");pGetSetProjectInfo=(GetSetProjectInfo_t)F("GetSetProjectInfo");pGetProjectStateChangeCount=(GetProjectStateChangeCount_t)F("GetProjectStateChangeCount");pGetPlayRate=(GetPlayRate_t)F("GetPlayRate");pMaster_GetTempo=(Master_GetTempo_t)F("Master_GetTempo");pGetProjectLength=(GetProjectLength_t)F("GetProjectLength");if(!pGetPlayPositionEx||!pGetPlayStateEx||!pEnumProjects||!pEnumProjectMarkers3||!pCountProjectMarkers||!pGetProjectName)return 0;WSADATA w{};if(WSAStartup(MAKEWORD(2,2),&w))return 0;g_sock=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);g_dest.sin_family=AF_INET;g_dest.sin_port=htons(19101);inet_pton(AF_INET,"127.0.0.1",&g_dest.sin_addr);rec->Register("ext_name",(void*)"SOWN REAPER Bridge");rec->Register("ext_vendor",(void*)"Sown Lighting");rec->Register("timer",(void*)timer);return 1;}
