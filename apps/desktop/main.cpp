#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <chrono>
#include <memory>
#include <string>
#include <vector>
#include "sown/ReaperSyncSource.hpp"
#include "sown/SyncSourceManager.hpp"
#include "sown/SyncEngine.hpp"
#include "sown/CueEngine.hpp"
#include "sown/Time.hpp"

using namespace sown;

static std::shared_ptr<ReaperSyncSource> g_reaper;
static std::shared_ptr<SyncSourceManager> g_sources;
static std::unique_ptr<SyncEngine> g_sync;
static CueEngine g_cues;
static std::uint64_t g_lastPackets=0;
static HFONT g_font=nullptr,g_big=nullptr,g_title=nullptr;
static HBRUSH g_bg=nullptr,g_panel=nullptr,g_panel2=nullptr;
static const COLORREF BG=RGB(10,15,22), PANEL=RGB(17,24,34), PANEL2=RGB(22,31,43);
static const COLORREF TEXT=RGB(231,238,247), MUTED=RGB(130,145,164), BLUE=RGB(45,156,255), GREEN=RGB(46,213,115), RED=RGB(255,82,105);

static void fill(HDC dc,RECT r,COLORREF c){HBRUSH b=CreateSolidBrush(c);FillRect(dc,&r,b);DeleteObject(b);}
static void txt(HDC dc,int x,int y,const std::wstring&s,COLORREF c,HFONT f=nullptr){
 SetBkMode(dc,TRANSPARENT);SetTextColor(dc,c);SelectObject(dc,f?f:g_font);TextOutW(dc,x,y,s.c_str(),(int)s.size());
}
static std::wstring ws(const std::string&s){return std::wstring(s.begin(),s.end());}
static void card(HDC dc,int x,int y,int w,int h){RECT r{x,y,x+w,y+h};fill(dc,r,PANEL);}
static void line(HDC dc,int x1,int y1,int x2,int y2,COLORREF c){HPEN p=CreatePen(PS_SOLID,1,c);auto o=SelectObject(dc,p);MoveToEx(dc,x1,y1,nullptr);LineTo(dc,x2,y2);SelectObject(dc,o);DeleteObject(p);}
static std::wstring timeText(TimeNs ns){return ws(formatDuration(ns));}

static LRESULT CALLBACK wndProc(HWND h,UINT m,WPARAM w,LPARAM l){
 if(m==WM_CREATE){SetTimer(h,1,50,nullptr);return 0;}
 if(m==WM_TIMER){InvalidateRect(h,nullptr,FALSE);return 0;}
 if(m==WM_ERASEBKGND)return 1;
 if(m==WM_KEYDOWN&&w==VK_ESCAPE){DestroyWindow(h);return 0;}
 if(m==WM_DESTROY){KillTimer(h,1);if(g_reaper)g_reaper->stop();PostQuitMessage(0);return 0;}
 if(m==WM_PAINT){
  PAINTSTRUCT ps{};HDC dc=BeginPaint(h,&ps);RECT cr{};GetClientRect(h,&cr);fill(dc,cr,BG);
  const int W=cr.right,H=cr.bottom;
  SyncState st=g_sync?g_sync->state():SyncState{};
  auto pc=g_reaper?g_reaper->packetsReceived():0;
  if(g_reaper&&pc!=g_lastPackets){g_cues.setCues(g_reaper->markerCues());g_lastPackets=pc;}
  auto cue=g_cues.evaluate(st.positionNs);

  // Top bar
  RECT top{0,0,W,64};fill(dc,top,RGB(12,18,27));
  txt(dc,24,16,L"SOWN SYNC",TEXT,g_title);txt(dc,160,22,L"SHOW SYNC SYSTEM",MUTED);
  txt(dc,W-170,22,st.connected?L"●  Connected":L"●  Waiting",st.connected?GREEN:MUTED);

  // Left source rail
  const int left=250;card(dc,16,80,left-28,H-96);txt(dc,32,98,L"SYNC SOURCES",MUTED);
  RECT sr{28,132,left-24,210};fill(dc,sr,st.connected?RGB(17,42,36):PANEL2);
  txt(dc,44,148,L"REAPER",TEXT);txt(dc,44,174,st.connected?L"●  Connected":L"●  Disconnected",st.connected?GREEN:MUTED);
  txt(dc,154,148,L"PRIMARY",GREEN);
  txt(dc,32,H-140,L"SOURCE",MUTED);txt(dc,32,H-114,L"REAPER",TEXT);
  txt(dc,32,H-82,L"PROJECT",MUTED);txt(dc,32,H-56,g_reaper?ws(g_reaper->projectName()):L"--",TEXT);

  // Main transport
  const int mx=left+16,mw=W-left-32;card(dc,mx,80,mw,238);
  txt(dc,mx+22,98,L"TRANSPORT",MUTED);
  const wchar_t* tr=st.transport==TransportState::Playing?L"PLAYING":(st.transport==TransportState::Paused?L"PAUSED":L"STOPPED");
  COLORREF tc=st.transport==TransportState::Playing?GREEN:(st.transport==TransportState::Paused?BLUE:RED);
  txt(dc,mx+22,132,tr,tc,g_title);
  txt(dc,mx+22,177,L"POSITION",MUTED);txt(dc,mx+22,201,timeText(st.positionNs),TEXT,g_big);
  // simple timeline
  line(dc,mx+24,276,mx+mw-24,276,RGB(52,65,80));
  int playX=mx+24+(int)((mw-48)*((st.positionNs/1e9)/300.0)); if(playX>mx+mw-24)playX=mx+mw-24;
  line(dc,playX,252,playX,292,BLUE);
  txt(dc,mx+24,294,L"0:00",MUTED);txt(dc,mx+mw-70,294,L"5:00",MUTED);

  // Cue cards
  int cy=334;card(dc,mx,cy,mw,150);txt(dc,mx+22,cy+18,L"SHOW CUES",MUTED);
  txt(dc,mx+22,cy+52,L"CURRENT",MUTED);
  txt(dc,mx+22,cy+78,cue.current?ws(cue.current->name):L"No current cue",TEXT);
  line(dc,mx+mw/2,cy+48,mx+mw/2,cy+126,RGB(42,52,65));
  txt(dc,mx+mw/2+24,cy+52,L"NEXT",MUTED);
  txt(dc,mx+mw/2+24,cy+78,cue.next?ws(cue.next->name):L"No upcoming cue",TEXT);
  if(cue.next){txt(dc,mx+mw/2+24,cy+105,L"In  "+timeText(cue.countdownNs),BLUE);}

  // Clean operator status only — internal estimator diagnostics intentionally hidden.
  int sy=500;card(dc,mx,sy,mw,H-sy-16);txt(dc,mx+22,sy+18,L"SYSTEM STATUS",MUTED);
  txt(dc,mx+22,sy+54,L"Sync",MUTED);txt(dc,mx+110,sy+54,st.locked?L"Ready":(st.connected?L"Connecting":L"Offline"),st.locked?GREEN:(st.connected?BLUE:MUTED));
  txt(dc,mx+250,sy+54,L"Source",MUTED);txt(dc,mx+330,sy+54,L"REAPER",TEXT);
  txt(dc,mx+470,sy+54,L"Markers",MUTED);txt(dc,mx+550,sy+54,std::to_wstring(g_cues.cues().size()),TEXT);
  txt(dc,mx+22,sy+92,L"Advanced timing diagnostics are kept inside the core and logs.",MUTED);
  EndPaint(h,&ps);return 0;
 }
 return DefWindowProcW(h,m,w,l);
}

int WINAPI wWinMain(HINSTANCE hi,HINSTANCE,LPWSTR,int show){
 g_font=CreateFontW(18,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
 g_title=CreateFontW(24,0,0,0,FW_SEMIBOLD,0,0,0,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
 g_big=CreateFontW(42,0,0,0,FW_SEMIBOLD,0,0,0,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Consolas");
 g_reaper=std::make_shared<ReaperSyncSource>(19101);g_reaper->start();
 g_sources=std::make_shared<SyncSourceManager>();g_sources->addSource("reaper","REAPER",g_reaper,SourceRole::Primary,10);
 g_sync=std::make_unique<SyncEngine>(g_sources);
 WNDCLASSW wc{};wc.lpfnWndProc=wndProc;wc.hInstance=hi;wc.lpszClassName=L"SownSyncDesktop";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);RegisterClassW(&wc);
 HWND h=CreateWindowExW(0,wc.lpszClassName,L"SOWN SYNC v0.3.0",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,1280,760,nullptr,nullptr,hi,nullptr);
 ShowWindow(h,show);UpdateWindow(h);MSG msg{};while(GetMessageW(&msg,nullptr,0,0)){TranslateMessage(&msg);DispatchMessageW(&msg);}
 DeleteObject(g_font);DeleteObject(g_title);DeleteObject(g_big);return 0;
}
#else
int main(){return 0;}
#endif
