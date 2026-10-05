import 'dart:async';
import 'dart:ffi';
import 'dart:ui' show FontFeature;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

const kRed=Color(0xFFFF334D), kBg=Color(0xFF080A0E), kPanel=Color(0xFF10141B), kLine=Color(0xFF252B35);
final class NativeState extends Struct{@Int32() external int connected;@Int32() external int locked;@Int32() external int transport;@Int64() external int positionNs;@Double() external double playbackRate;@Double() external double fps;@Uint64() external int sequence;}
final class NativeCue extends Struct{@Uint32() external int id;@Int64() external int timeNs;@Int64() external int warningNs;@Array(64) external Array<Uint8> department;@Array(192) external Array<Uint8> name;@Int32() external int valid;}
typedef InitN=Int32 Function(); typedef InitD=int Function(); typedef ShutN=Void Function(); typedef ShutD=void Function();
typedef StateN=Int32 Function(Pointer<NativeState>); typedef StateD=int Function(Pointer<NativeState>);
typedef CueN=Int32 Function(Pointer<NativeCue>); typedef CueD=int Function(Pointer<NativeCue>);
typedef NextN=Int32 Function(Pointer<NativeCue>,Pointer<Int64>); typedef NextD=int Function(Pointer<NativeCue>,Pointer<Int64>);
typedef CountN=Int32 Function(); typedef CountD=int Function(); typedef StrN=Pointer<Utf8> Function(); typedef StrD=Pointer<Utf8> Function();

class CueView{final int id,timeNs;final String department,name;const CueView(this.id,this.timeNs,this.department,this.name);}
String _fixed(Array<Uint8> a,int n){final b=<int>[];for(var i=0;i<n&&a[i]!=0;i++)b.add(a[i]);return String.fromCharCodes(b);}
class CoreBridge{
 late DynamicLibrary l;late InitD init;late ShutD shut;late StateD state;late CueD current;late NextD next;late CountD count;late StrD project,source;bool loaded=false;
 bool open(){try{l=DynamicLibrary.open('sown_core_api.dll');init=l.lookupFunction<InitN,InitD>('sown_init');shut=l.lookupFunction<ShutN,ShutD>('sown_shutdown');state=l.lookupFunction<StateN,StateD>('sown_get_state');current=l.lookupFunction<CueN,CueD>('sown_get_current_cue');next=l.lookupFunction<NextN,NextD>('sown_get_next_cue');count=l.lookupFunction<CountN,CountD>('sown_get_cue_count');project=l.lookupFunction<StrN,StrD>('sown_get_project_name');source=l.lookupFunction<StrN,StrD>('sown_get_active_source');loaded=init()==1;return loaded;}catch(_){return false;}}
 CueView? cue(bool isNext,Pointer<Int64>? cd){final p=calloc<NativeCue>();try{final ok=isNext?next(p,cd!):current(p);if(ok!=1||p.ref.valid==0)return null;return CueView(p.ref.id,p.ref.timeNs,_fixed(p.ref.department,64),_fixed(p.ref.name,192));}finally{calloc.free(p);}}
 void close(){if(loaded)shut();}
}
void main()=>runApp(const SownApp());
class SownApp extends StatelessWidget{const SownApp({super.key});@override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'SOWN SYNC',theme:ThemeData(useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:kBg,colorScheme:ColorScheme.fromSeed(seedColor:kRed,brightness:Brightness.dark),fontFamily:'Segoe UI'),home:const Workspace());}
class Workspace extends StatefulWidget{const Workspace({super.key});@override State<Workspace> createState()=>_WorkspaceState();}
class _WorkspaceState extends State<Workspace>{
 final core=CoreBridge();Timer? timer;bool native=false,connected=false,locked=false;int transport=0,pos=0,cueCount=0,countdown=0;double fps=0;String project='Waiting for show',source='REAPER';CueView? current,next;int page=0;
 @override void initState(){super.initState();native=core.open();timer=Timer.periodic(const Duration(milliseconds:50),(_)=>poll());}
 void poll(){if(!native)return;final s=calloc<NativeState>(),cd=calloc<Int64>();try{if(core.state(s)==1&&mounted){final cv=core.cue(false,null),nv=core.cue(true,cd);setState((){connected=s.ref.connected!=0;locked=s.ref.locked!=0;transport=s.ref.transport;pos=s.ref.positionNs;fps=s.ref.fps;project=core.project().toDartString();source=core.source().toDartString().toUpperCase();cueCount=core.count();current=cv;next=nv;countdown=cd.value;});}}finally{calloc.free(s);calloc.free(cd);}}
 @override void dispose(){timer?.cancel();core.close();super.dispose();}
 String clock(int ns,{bool millis=true}){final ms=ns~/1000000,h=ms~/3600000,m=(ms~/60000)%60,s=(ms~/1000)%60,x=ms%1000;String p(int v,int n)=>v.toString().padLeft(n,'0');return millis?'${p(h,2)}:${p(m,2)}:${p(s,2)}.${p(x,3)}':'${p(h,2)}:${p(m,2)}:${p(s,2)}';}
 @override Widget build(BuildContext context){return Scaffold(body:Row(children:[_nav(),Expanded(child:Column(children:[_top(),Expanded(child:page==0?_show():_placeholder())]))]));}
 Widget _nav() {
   const icons = [Icons.live_tv_rounded, Icons.timeline_rounded, Icons.format_list_bulleted_rounded, Icons.cable_rounded, Icons.settings_rounded];
   const names = ['SHOW', 'TIMELINE', 'CUES', 'SOURCES', 'SETTINGS'];
   return Container(
     width: 88,
     color: const Color(0xFF0C1016),
     child: Column(children: [
       const SizedBox(height: 18),
       Container(width: 44, height: 44, decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.grid_view_rounded)),
       const SizedBox(height: 22),
       ...List.generate(5, (i) => InkWell(
         onTap: () => setState(() => page = i),
         child: Container(
           width: 88,
           padding: const EdgeInsets.symmetric(vertical: 13),
           decoration: BoxDecoration(border: Border(left: BorderSide(color: page == i ? kRed : Colors.transparent, width: 3))),
           child: Column(children: [
             Icon(icons[i], size: 21, color: page == i ? Colors.white : Colors.white38),
             const SizedBox(height: 5),
             Text(names[i], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: page == i ? Colors.white : Colors.white38)),
           ]),
         ),
       )),
     ]),
   );
 }
 Widget _top() {
   return Container(
     height: 72,
     padding: const EdgeInsets.symmetric(horizontal: 28),
     decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
     child: Row(children: [
       const Text('SOWN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
       const Text(' SYNC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kRed, letterSpacing: 1)),
       const SizedBox(width: 28),
       Container(width: 1, height: 22, color: kLine),
       const SizedBox(width: 20),
       Expanded(child: Text(project.isEmpty ? 'UNTITLED SHOW' : project, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
       _pill(connected ? 'CONNECTED' : 'OFFLINE', connected ? Colors.greenAccent : Colors.white38),
     ]),
   );
 }
 Widget _show() {
   return LayoutBuilder(builder: (context, constraints) {
     final narrow = constraints.maxWidth < 760;
     final compact = constraints.maxWidth < 1180 || constraints.maxHeight < 720;
     if (narrow) {
       return SingleChildScrollView(
         padding: const EdgeInsets.all(10),
         child: Column(children: [
           _hero(true),
           const SizedBox(height: 10),
           SizedBox(height: 330, child: _cueDeck(compact: true, stacked: true)),
           const SizedBox(height: 10),
           SizedBox(height: 76, child: _compactStatus(minimal: true)),
         ]),
       );
     }
     return Padding(
       padding: EdgeInsets.all(compact ? 12 : 18),
       child: Column(children: [
         _hero(compact),
         SizedBox(height: compact ? 10 : 12),
         Expanded(
           child: Row(children: [
             Expanded(child: _cueDeck(compact: compact)),
             if (!compact) ...[
               const SizedBox(width: 12),
               SizedBox(width: 250, child: _rightRail()),
             ],
           ]),
         ),
         if (compact) ...[
           const SizedBox(height: 10),
           SizedBox(height: 76, child: _compactStatus()),
         ],
       ]),
     );
   });
 }

 Widget _hero(bool compact) {
   final playing = transport == 1;
   final paused = transport == 2;
   final tcColor = playing ? Colors.greenAccent : paused ? Colors.orangeAccent : kRed;
   final fpsText = fps > 0 ? fps.toStringAsFixed(2) : '--';
   final nextText = next != null ? 'NEXT  ${clock(countdown)}' : 'NO UPCOMING CUE';
   return Container(
     height: compact ? 190 : 220,
     padding: EdgeInsets.fromLTRB(compact ? 18 : 26, 16, compact ? 18 : 26, 14),
     decoration: _box(),
     child: Column(children: [
       Row(children: [
         _label('MASTER TIMECODE'),
         const Spacer(),
         _pill(playing ? 'PLAYING' : paused ? 'PAUSED' : 'STOPPED', tcColor),
       ]),
       const Spacer(),
       FittedBox(
         fit: BoxFit.scaleDown,
         child: Text(
           clock(pos),
           style: TextStyle(
             fontSize: compact ? 46 : 60,
             fontWeight: FontWeight.w300,
             letterSpacing: 2,
             fontFeatures: const [FontFeature.tabularFigures()],
           ),
         ),
       ),
       const SizedBox(height: 4),
       Text('$fpsText FPS   •   $source MASTER', style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.1)),
       const Spacer(),
       _timeline(),
       const SizedBox(height: 5),
       Row(children: [
         Text(clock(pos, millis: false), style: const TextStyle(color: Colors.white38, fontSize: 10)),
         const Spacer(),
         Flexible(child: Text(nextText, overflow: TextOverflow.ellipsis, style: TextStyle(color: next != null ? kRed : Colors.white24, fontSize: 10, fontWeight: FontWeight.w700))),
       ]),
     ]),
   );
 }

 Widget _timeline() {
   return LayoutBuilder(builder: (context, constraints) {
     return SizedBox(
       height: 26,
       child: Stack(children: [
         Positioned(top: 13, left: 0, right: 0, child: Container(height: 1, color: kLine)),
         Positioned(top: 5, left: constraints.maxWidth * .5 - 1, child: Container(width: 2, height: 17, color: kRed)),
         ...List.generate(9, (i) => Positioned(
           left: constraints.maxWidth * i / 8 - .5,
           top: 10,
           child: Container(width: 1, height: 7, color: Colors.white12),
         )),
       ]),
     );
   });
 }

 Widget _cueDeck({bool compact = false, bool stacked = false}) {
   return Container(
     padding: EdgeInsets.all(compact ? 14 : 18),
     decoration: _box(),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [_label('SHOW CUES'), const Spacer(), Text('$cueCount CUES', style: const TextStyle(color: Colors.white38, fontSize: 10))]),
       const SizedBox(height: 12),
       Expanded(
         child: stacked
             ? Column(children: [
                 Expanded(child: _cueCard('CURRENT', current, false, true)),
                 const SizedBox(height: 8),
                 Expanded(child: _cueCard('NEXT', next, true, true)),
               ])
             : Row(children: [
                 Expanded(flex: 4, child: _cueCard('CURRENT', current, false, compact)),
                 const SizedBox(width: 10),
                 Expanded(flex: 6, child: _cueCard('NEXT', next, true, compact)),
               ]),
       ),
     ]),
   );
 }

 Widget _cueCard(String title, CueView? cue, bool upcoming, bool compact) {
   return Container(
     padding: EdgeInsets.all(compact ? 14 : 18),
     decoration: BoxDecoration(
       color: upcoming ? kRed.withValues(alpha: .055) : Colors.white.withValues(alpha: .025),
       borderRadius: BorderRadius.circular(12),
       border: Border.all(color: upcoming && cue != null ? kRed.withValues(alpha: .42) : kLine),
     ),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [
         _label(title),
         const Spacer(),
         if (cue != null) Flexible(child: _pill(cue.department.isEmpty ? 'CUE' : cue.department, upcoming ? kRed : Colors.white54)),
       ]),
       const Spacer(),
       Text(
         cue == null ? '—' : cue.name,
         overflow: TextOverflow.ellipsis,
         maxLines: 2,
         style: TextStyle(fontSize: compact ? 21 : (upcoming ? 27 : 24), fontWeight: FontWeight.w700, height: 1.05, color: cue == null ? Colors.white24 : Colors.white),
       ),
       const SizedBox(height: 8),
       if (cue != null) Text('#${cue.id}   ${clock(cue.timeNs)}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
       const Spacer(),
       if (upcoming)
         FittedBox(
           fit: BoxFit.scaleDown,
           alignment: Alignment.centerLeft,
           child: Text(
             cue == null ? 'READY' : 'IN  ${clock(countdown)}',
             style: TextStyle(fontSize: compact ? 19 : 24, fontWeight: FontWeight.w800, color: cue == null ? Colors.white38 : kRed, fontFeatures: const [FontFeature.tabularFigures()]),
           ),
         ),
     ]),
   );
 }

 Widget _rightRail() {
   return Column(children: [
     Expanded(child: _statusPanel()),
     const SizedBox(height: 14),
     Expanded(child: _sourcePanel()),
   ]);
 }

 Widget _statusPanel() {
   final syncText = locked ? 'READY' : connected ? 'ACQUIRING' : 'OFFLINE';
   final syncColor = locked ? Colors.greenAccent : connected ? Colors.orangeAccent : Colors.white38;
   final transportText = transport == 1 ? 'PLAYING' : transport == 2 ? 'PAUSED' : 'STOPPED';
   final transportColor = transport == 1 ? Colors.greenAccent : transport == 2 ? Colors.orangeAccent : kRed;
   return Container(
     padding: const EdgeInsets.all(18),
     decoration: _box(),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       _label('SHOW STATUS'),
       const Spacer(),
       _metric('SYNC', syncText, syncColor),
       const SizedBox(height: 12),
       _metric('TRANSPORT', transportText, transportColor),
       const SizedBox(height: 12),
       _metric('CUES', '$cueCount', Colors.white),
       const Spacer(),
     ]),
   );
 }

 Widget _sourcePanel() {
   return Container(
     padding: const EdgeInsets.all(18),
     decoration: _box(),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       _label('TIME SOURCE'),
       const Spacer(),
       Row(children: [
         Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: connected ? Colors.greenAccent : Colors.white24)),
         const SizedBox(width: 12),
         Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
           Text(source.isEmpty ? 'NO SOURCE' : source, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
           const SizedBox(height: 3),
           Text(connected ? 'PRIMARY • CONNECTED' : 'WAITING FOR SOURCE', style: const TextStyle(color: Colors.white38, fontSize: 9)),
         ])),
       ]),
       const Spacer(),
       Text(native ? 'CORE v0.5.0' : 'CORE NOT LOADED', style: const TextStyle(color: Colors.white24, fontSize: 9)),
     ]),
   );
 }

 Widget _compactStatus({bool minimal = false}) {
   final syncText = locked ? 'SYNC READY' : connected ? 'SYNCING' : 'OFFLINE';
   final transportText = transport == 1 ? 'PLAYING' : transport == 2 ? 'PAUSED' : 'STOPPED';
   return Container(
     padding: EdgeInsets.symmetric(horizontal: minimal ? 12 : 18, vertical: 10),
     decoration: _box(),
     child: Row(children: [
       _statusDot(connected ? Colors.greenAccent : Colors.white24),
       const SizedBox(width: 9),
       Flexible(child: Text(source.isEmpty ? 'NO SOURCE' : source, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
       const SizedBox(width: 14),
       _miniStatus('SYNC', syncText, locked ? Colors.greenAccent : Colors.orangeAccent),
       if (!minimal) ...[
         const SizedBox(width: 22),
         _miniStatus('TRANSPORT', transportText, transport == 1 ? Colors.greenAccent : transport == 2 ? Colors.orangeAccent : kRed),
         const SizedBox(width: 22),
         _miniStatus('CUES', '$cueCount', Colors.white),
       ],
     ]),
   );
 }

 Widget _miniStatus(String label, String value, Color color) {
   return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
     Text(label, style: const TextStyle(color: Colors.white30, fontSize: 8, fontWeight: FontWeight.w700)),
     const SizedBox(height: 3),
     Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
   ]);
 }

 Widget _statusDot(Color color) => Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));

 Widget _placeholder() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
   const Icon(Icons.construction_rounded, size: 36, color: Colors.white24),
   const SizedBox(height: 12),
   Text(['SHOW', 'TIMELINE', 'CUES', 'SOURCES', 'SETTINGS'][page], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
   const SizedBox(height: 6),
   const Text('Workspace coming in the next UI iteration', style: TextStyle(color: Colors.white38)),
 ]));

 BoxDecoration _box() => BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine));
 Widget _label(String s) => Text(s, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2));
 Widget _pill(String s, Color color) => Container(
   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
   decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .14))),
   child: Text('●  $s', overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
 );
 Widget _metric(String label, String value, Color color) => Row(children: [
   Expanded(child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9))),
   Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
 ]);

}
