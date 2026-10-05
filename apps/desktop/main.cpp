#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <vector>
#include "sown/ReaperSyncSource.hpp"
#include "sown/SyncSourceManager.hpp"
#include "sown/SyncEngine.hpp"
#include "sown/CueEngine.hpp"
#include "sown/Time.hpp"
using namespace sown;

static std::shared_ptr<ReaperSyncSource> R; static std::shared_ptr<SyncSourceManager> M;
static std::unique_ptr<SyncEngine> E; static CueEngine C; static std::uint64_t lastP=0;
static HFONT f12,f14,f18,f24,f34,fMono;
static COLORREF bg=RGB(7,11,17),surface=RGB(13,19,28),cardc=RGB(18,26,38),border=RGB(36,48,64);
static COLORREF textc=RGB(235,241,248),muted=RGB(127,145,168),blue=RGB(42,151,255),green=RGB(44,214,120),red=RGB(255,76,103),amber=RGB(255,184,77);

static void box(HDC d,int x,int y,int w,int h,COLORREF c){RECT r{x,y,x+w,y+h};HBRUSH b=CreateSolidBrush(c);FillRect(d,&r,b);DeleteObject(b);}
static void line(HDC d,int x1,int y1,int x2,int y2,COLORREF c,int n=1){HPEN p=CreatePen(PS_SOLID,n,c);auto o=SelectObject(d,p);MoveToEx(d,x1,y1,0);LineTo(d,x2,y2);SelectObject(d,o);DeleteObject(p);}
static void t(HDC d,int x,int y,const std::wstring&s,COLORREF c,HFONT f){SetBkMode(d,TRANSPARENT);SetTextColor(d,c);SelectObject(d,f);TextOutW(d,x,y,s.c_str(),(int)s.size());}
static std::wstring W(const std::string&s){return std::wstring(s.begin(),s.end());}
static std::wstring T(TimeNs n){return W(formatDuration(n));}
static void pill(HDC d,int x,int y,const std::wstring&s,COLORREF c){box(d,x,y,112,28,RGB(20,31,42));t(d,x+12,y+5,s,c,f12);}
static void iconButton(HDC d,int x,int y,const wchar_t*s,bool hot=false){box(d,x,y,46,38,hot?RGB(25,105,165):RGB(24,33,46));t(d,x+15,y+7,s,hot?RGB(255,255,255):textc,f18);}
static std::wstring cueName(const std::optional<Cue>&c){return c?W(c->name):L"—";}
static std::wstring cueDept(const std::optional<Cue>&c){return c?W(c->department):L"";}

static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
 if(m==WM_CREATE){SetTimer(h,1,50,0);return 0;} if(m==WM_TIMER){InvalidateRect(h,0,FALSE);return 0;} if(m==WM_ERASEBKGND)return 1;
 if(m==WM_KEYDOWN&&w==VK_ESCAPE){DestroyWindow(h);return 0;}
 if(m==WM_DESTROY){KillTimer(h,1);if(R)R->stop();PostQuitMessage(0);return 0;}
 if(m!=WM_PAINT)return DefWindowProcW(h,m,w,l);
 PAINTSTRUCT p{};HDC d=BeginPaint(h,&p);RECT rc{};GetClientRect(h,&rc);int WW=rc.right,HH=rc.bottom;box(d,0,0,WW,HH,bg);
 SyncState s=E?E->state():SyncState{};auto packets=R?R->packetsReceived():0;if(R&&packets!=lastP){C.setCues(R->markerCues());lastP=packets;}auto q=C.evaluate(s.positionNs);
 const wchar_t* tr=s.transport==TransportState::Playing?L"PLAYING":s.transport==TransportState::Paused?L"PAUSED":L"STOPPED";
 COLORREF trc=s.transport==TransportState::Playing?green:s.transport==TransportState::Paused?amber:red;

 // Header
 box(d,0,0,WW,68,surface);t(d,22,14,L"SOWN",RGB(255,255,255),f24);t(d,95,14,L"SYNC",blue,f24);t(d,22,43,L"SHOW CONTROL",muted,f12);
 int nx=250;t(d,nx,24,L"HOME",blue,f14);t(d,nx+85,24,L"SOURCES",muted,f14);t(d,nx+190,24,L"CUES",muted,f14);t(d,nx+265,24,L"SETTINGS",muted,f14);
 pill(d,WW-150,20,s.connected?L"●  ONLINE":L"●  OFFLINE",s.connected?green:red);

 // Sidebar
 int side=286;box(d,14,82,side-28,HH-96,surface);t(d,30,102,L"SOURCES",muted,f12);
 box(d,26,132,side-52,94,s.connected?RGB(13,43,36):cardc);line(d,26,132,26,226,s.connected?green:red,3);
 t(d,44,149,L"REAPER",textc,f18);pill(d,142,145,L"PRIMARY",green);t(d,44,183,s.connected?L"● Connected":L"● Disconnected",s.connected?green:red,f12);
 t(d,30,254,L"SHOW",muted,f12);t(d,30,280,R&&!R->projectName().empty()?W(R->projectName()):L"No project",textc,f14);
 line(d,30,315,side-30,315,border);t(d,30,338,L"QUICK STATUS",muted,f12);
 t(d,30,368,L"Sync",muted,f12);t(d,112,368,s.locked?L"Ready":s.connected?L"Connecting":L"Offline",s.locked?green:s.connected?amber:red,f14);
 t(d,30,400,L"Cues",muted,f12);t(d,112,400,std::to_wstring(C.cues().size()),textc,f14);
 t(d,30,432,L"Transport",muted,f12);t(d,112,432,tr,trc,f14);

 int x=side+14,wmain=WW-x-14;
 // Hero transport
 box(d,x,82,wmain,222,surface);t(d,x+22,101,L"TRANSPORT",muted,f12);pill(d,x+wmain-142,96,tr,trc);
 t(d,x+22,132,L"MASTER POSITION",muted,f12);t(d,x+20,154,T(s.positionNs),textc,f34);
 // transport buttons visual
 int bx=x+wmain-360,by=145;iconButton(d,bx,by,L"◀");iconButton(d,bx+56,by,L"■");iconButton(d,bx+112,by,L"▶",s.transport==TransportState::Playing);iconButton(d,bx+168,by,L"Ⅱ",s.transport==TransportState::Paused);iconButton(d,bx+224,by,L"▶");
 // timeline
 int lx=x+22,rx=x+wmain-22,ly=245;line(d,lx,ly,rx,ly,border,2);
 double sec=(double)s.positionNs/1e9, span=300.0;int px=lx+(int)((rx-lx)*std::clamp(sec/span,0.0,1.0));line(d,px,ly-15,px,ly+20,blue,2);
 for(int i=0;i<=10;i++){int xx=lx+(rx-lx)*i/10;line(d,xx,ly-4,xx,ly+5,border);if(i%2==0)t(d,xx-10,ly+12,std::to_wstring(i*30)+L"s",muted,f12);}

 // Cue focus
 int cy=318,ch=198;box(d,x,cy,wmain,ch,surface);t(d,x+22,cy+18,L"SHOW CUES",muted,f12);
 int half=wmain/2;box(d,x+20,cy+48,half-30,126,cardc);box(d,x+half+10,cy+48,half-30,126,cardc);
 t(d,x+38,cy+64,L"CURRENT",muted,f12);t(d,x+38,cy+90,cueName(q.current),textc,f24);if(q.current)t(d,x+38,cy+126,cueDept(q.current),blue,f12);
 t(d,x+half+28,cy+64,L"NEXT",muted,f12);t(d,x+half+28,cy+90,cueName(q.next),textc,f24);
 if(q.next){t(d,x+half+28,cy+126,L"IN  "+T(q.countdownNs),blue,f18);}

 // Bottom operational strip
 int sy=530;box(d,x,sy,wmain,HH-sy-14,surface);t(d,x+22,sy+18,L"OVERVIEW",muted,f12);
 int cw=(wmain-88)/3;
 box(d,x+22,sy+50,cw,86,cardc);t(d,x+38,sy+64,L"SYNC",muted,f12);t(d,x+38,sy+90,s.locked?L"READY":s.connected?L"CONNECTING":L"OFFLINE",s.locked?green:s.connected?amber:red,f18);
 box(d,x+44+cw,sy+50,cw,86,cardc);t(d,x+60+cw,sy+64,L"SOURCE",muted,f12);t(d,x+60+cw,sy+90,L"REAPER",textc,f18);
 box(d,x+66+cw*2,sy+50,cw,86,cardc);t(d,x+82+cw*2,sy+64,L"NEXT CUE",muted,f12);t(d,x+82+cw*2,sy+90,q.next?T(q.countdownNs):L"—",q.next?blue:muted,f18);
 t(d,x+22,HH-40,L"ESC  Close",muted,f12);t(d,WW-210,HH-40,L"SOWN SYNC  v0.3.0",muted,f12);
 EndPaint(h,&p);return 0;
}
static HFONT font(int n,int weight,const wchar_t*name=L"Segoe UI"){return CreateFontW(n,0,0,0,weight,0,0,0,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,name);}
int WINAPI wWinMain(HINSTANCE hi,HINSTANCE,LPWSTR,int show){
 f12=font(14,FW_NORMAL);f14=font(17,FW_NORMAL);f18=font(20,FW_SEMIBOLD);f24=font(28,FW_SEMIBOLD);f34=font(42,FW_SEMIBOLD,L"Consolas");fMono=font(18,FW_NORMAL,L"Consolas");
 R=std::make_shared<ReaperSyncSource>(19101);R->start();M=std::make_shared<SyncSourceManager>();M->addSource("reaper","REAPER",R,SourceRole::Primary,10);E=std::make_unique<SyncEngine>(M);
 WNDCLASSW wc{};wc.lpfnWndProc=proc;wc.hInstance=hi;wc.lpszClassName=L"SownSyncDesktopV2";wc.hCursor=LoadCursor(0,IDC_ARROW);RegisterClassW(&wc);
 HWND h=CreateWindowExW(0,wc.lpszClassName,L"SOWN SYNC",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,1440,860,0,0,hi,0);ShowWindow(h,show);UpdateWindow(h);
 MSG msg{};while(GetMessageW(&msg,0,0,0)){TranslateMessage(&msg);DispatchMessageW(&msg);}
 for(auto f:{f12,f14,f18,f24,f34,fMono})DeleteObject(f);return 0;
}
#else
int main(){return 0;}
#endif
