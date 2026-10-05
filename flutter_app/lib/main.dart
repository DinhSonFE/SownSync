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
typedef CountN=Int32 Function(); typedef CountD=int Function(); typedef CueAtN=Int32 Function(Int32,Pointer<NativeCue>); typedef CueAtD=int Function(int,Pointer<NativeCue>); typedef StrN=Pointer<Utf8> Function(); typedef StrD=Pointer<Utf8> Function();

class CueView{final int id,timeNs;final String department,name;const CueView(this.id,this.timeNs,this.department,this.name);}
String _fixed(Array<Uint8> a,int n){final b=<int>[];for(var i=0;i<n&&a[i]!=0;i++)b.add(a[i]);return String.fromCharCodes(b);}
class CoreBridge{
 late DynamicLibrary l;late InitD init;late ShutD shut;late StateD state;late CueD current;late NextD next;late CountD count;late CueAtD cueAt;late StrD project,source;bool loaded=false;
 bool open(){try{l=DynamicLibrary.open('sown_core_api.dll');init=l.lookupFunction<InitN,InitD>('sown_init');shut=l.lookupFunction<ShutN,ShutD>('sown_shutdown');state=l.lookupFunction<StateN,StateD>('sown_get_state');current=l.lookupFunction<CueN,CueD>('sown_get_current_cue');next=l.lookupFunction<NextN,NextD>('sown_get_next_cue');count=l.lookupFunction<CountN,CountD>('sown_get_cue_count');cueAt=l.lookupFunction<CueAtN,CueAtD>('sown_get_cue_at');project=l.lookupFunction<StrN,StrD>('sown_get_project_name');source=l.lookupFunction<StrN,StrD>('sown_get_active_source');loaded=init()==1;return loaded;}catch(_){return false;}}
 CueView? cue(bool isNext,Pointer<Int64>? cd){final p=calloc<NativeCue>();try{final ok=isNext?next(p,cd!):current(p);if(ok!=1||p.ref.valid==0)return null;return CueView(p.ref.id,p.ref.timeNs,_fixed(p.ref.department,64),_fixed(p.ref.name,192));}finally{calloc.free(p);}}
 List<CueView> allCues(){final out=<CueView>[];if(!loaded)return out;final n=count();for(var i=0;i<n;i++){final p=calloc<NativeCue>();try{if(cueAt(i,p)==1&&p.ref.valid!=0){out.add(CueView(p.ref.id,p.ref.timeNs,_fixed(p.ref.department,64),_fixed(p.ref.name,192)));}}finally{calloc.free(p);}}return out;}
 void close(){if(loaded)shut();}
}
void main()=>runApp(const SownApp());
class SownApp extends StatelessWidget{const SownApp({super.key});@override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'SOWN SYNC',theme:ThemeData(useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:kBg,colorScheme:ColorScheme.fromSeed(seedColor:kRed,brightness:Brightness.dark),fontFamily:'Segoe UI'),home:const Workspace());}
class Workspace extends StatefulWidget{const Workspace({super.key});@override State<Workspace> createState()=>_WorkspaceState();}
class _WorkspaceState extends State<Workspace>{
 final core=CoreBridge();Timer? timer;bool native=false,connected=false,locked=false;int transport=0,pos=0,cueCount=0,countdown=0;double fps=0;String project='Waiting for show',source='REAPER';CueView? current,next;List<CueView> cueList=[];int page=0;
 @override void initState(){super.initState();native=core.open();timer=Timer.periodic(const Duration(milliseconds:50),(_)=>poll());}
 void poll(){if(!native)return;final s=calloc<NativeState>(),cd=calloc<Int64>();try{if(core.state(s)==1&&mounted){final cv=core.cue(false,null),nv=core.cue(true,cd);setState((){connected=s.ref.connected!=0;locked=s.ref.locked!=0;transport=s.ref.transport;pos=s.ref.positionNs;fps=s.ref.fps;project=core.project().toDartString();source=core.source().toDartString().toUpperCase();cueCount=core.count();current=cv;next=nv;countdown=cd.value;cueList=core.allCues();});}}finally{calloc.free(s);calloc.free(cd);}}
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
             Text(names[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: page == i ? Colors.white : Colors.white38)),
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
       Container(width: 1, height: 18, color: kLine),
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
     final wide = constraints.maxWidth >= 1400;
     if (narrow) {
       return SingleChildScrollView(
         padding: const EdgeInsets.all(10),
         child: Column(children: [
           _hero(true),
           const SizedBox(height: 10),
           _operatorStrip(compact: true),
           const SizedBox(height: 10),
           SizedBox(height: 410, child: _cueDeck(compact: true, stacked: true)),
         ]),
       );
     }
     return Padding(
       padding: EdgeInsets.all(compact ? 12 : 16),
       child: Column(children: [
         _hero(compact, wide: wide),
         SizedBox(height: compact ? 10 : 12),
         _operatorStrip(compact: compact),
         SizedBox(height: compact ? 10 : 12),
         Expanded(child: Row(children:[Expanded(flex:5,child:_cueDeck(compact: compact)),SizedBox(width: compact?10:12),Expanded(flex:3,child:_cueListPanel(compact))])),
       ]),
     );
   });
 }

 Widget _hero(bool compact, {bool wide = false}) {
   final playing = transport == 1;
   final paused = transport == 2;
   final tcColor = playing ? Colors.greenAccent : paused ? Colors.orangeAccent : kRed;
   final fpsText = fps > 0 ? fps.toStringAsFixed(2) : '--';
   return Container(
     height: compact ? 210 : wide ? 310 : 250,
     padding: EdgeInsets.fromLTRB(compact ? 18 : 28, 16, compact ? 18 : 28, 14),
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
         child: Text(clock(pos), style: TextStyle(fontFamily: 'Consolas', fontSize: compact ? 72 : wide ? 138 : 96, fontWeight: FontWeight.w600, color: const Color(0xFFFF4057), letterSpacing: wide ? 6 : 4, fontFeatures: const [FontFeature.tabularFigures()], shadows: const [Shadow(color: Color(0x66FF334D), blurRadius: 16)])),
       ),
       const SizedBox(height: 2),
       Text('$fpsText FPS   •   $source MASTER', style: TextStyle(color: Colors.white54, fontSize: wide ? 13 : 11, fontWeight: FontWeight.w600, letterSpacing: 1.3)),
       const Spacer(),
       _timeline(),
     ]),
   );
 }

 Widget _timeline() {
   return LayoutBuilder(builder: (context, constraints) => SizedBox(
     height: 22,
     child: Stack(children: [
       Positioned(top: 9, left: 0, right: 0, child: Container(height: 1, color: kLine)),
       Positioned(top: 1, left: constraints.maxWidth * .5 - 1, child: Container(width: 2, height: 16, color: kRed)),
       ...List.generate(9, (i) => Positioned(left: constraints.maxWidth * i / 8 - .5, top: 6, child: Container(width: 1, height: 7, color: Colors.white12))),
     ]),
   ));
 }

 Widget _operatorStrip({bool compact = false}) {
   final syncText = locked ? 'READY' : connected ? 'ACQUIRING' : 'OFFLINE';
   final transportText = transport == 1 ? 'PLAYING' : transport == 2 ? 'PAUSED' : 'STOPPED';
   final transportColor = transport == 1 ? Colors.greenAccent : transport == 2 ? Colors.orangeAccent : kRed;
   return Container(
     height: compact ? 62 : 70,
     padding: const EdgeInsets.symmetric(horizontal: 18),
     decoration: _box(),
     child: Row(children: [
       _statusDot(connected ? Colors.greenAccent : Colors.white24),
       const SizedBox(width: 10),
       Flexible(child: Text(source.isEmpty ? 'NO SOURCE' : source, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
       const SizedBox(width: 18),
       _divider(),
       const SizedBox(width: 18),
       _miniStatus('SYNC', syncText, locked ? Colors.greenAccent : Colors.orangeAccent),
       const SizedBox(width: 26),
       _miniStatus('TRANSPORT', transportText, transportColor),
       if (!compact) ...[
         const SizedBox(width: 26),
         _miniStatus('CUES', '$cueCount', Colors.white),
       ],
       const Spacer(),
       if (next != null) ...[
         const Text('NEXT IN', style: TextStyle(color: Colors.white30, fontSize: 8, fontWeight: FontWeight.w800)),
         const SizedBox(width: 10),
         Text(clock(countdown), style: const TextStyle(color: kRed, fontSize: 20, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
       ],
     ]),
   );
 }

 Widget _cueDeck({bool compact = false, bool stacked = false}) {
   return Container(
     padding: EdgeInsets.all(compact ? 12 : 16),
     decoration: _box(),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [_label('SHOW CUES'), const Spacer(), Text('$cueCount CUES', style: const TextStyle(color: Colors.white30, fontSize: 9))]),
       const SizedBox(height: 10),
       Expanded(
         child: stacked
             ? Column(children: [
                 Expanded(child: _currentCard(compact)),
                 const SizedBox(height: 8),
                 Expanded(flex: 2, child: _nextCard(compact)),
               ])
             : Row(children: [
                 Expanded(flex: 5, child: _currentCard(compact)),
                 const SizedBox(width: 10),
                 Expanded(flex: 5, child: _nextCard(compact)),
               ]),
       ),
     ]),
   );
 }

 Widget _currentCard(bool compact) {
   return Container(
     padding: EdgeInsets.all(compact ? 14 : 18),
     decoration: BoxDecoration(color: Colors.white.withValues(alpha: .025), borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [_label('CURRENT'), const Spacer(), if (current != null) _pill(current!.department.isEmpty ? 'CUE' : current!.department, Colors.white54)]),
       const Spacer(),
       Text(current?.name ?? 'NO ACTIVE CUE', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 22 : 30, fontWeight: FontWeight.w700, color: current == null ? Colors.white24 : Colors.white)),
       const SizedBox(height: 7),
       if (current != null) Text('#${current!.id}   ${clock(current!.timeNs)}', style: const TextStyle(color: Colors.white38, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()])),
       const Spacer(),
       const Text('NOW', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
     ]),
   );
 }

 Widget _nextCard(bool compact) {
   final has = next != null;
   return Container(
     padding: EdgeInsets.all(compact ? 16 : 22),
     decoration: BoxDecoration(
       color: kRed.withValues(alpha: .065),
       borderRadius: BorderRadius.circular(12),
       border: Border.all(color: has ? kRed.withValues(alpha: .55) : kLine),
     ),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [
         _label('NEXT CUE'),
         const Spacer(),
         if (has) _pill(next!.department.isEmpty ? 'CUE' : next!.department, kRed),
       ]),
       const Spacer(),
       Text(has ? next!.name : 'READY', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 28 : 38, height: 1.05, fontWeight: FontWeight.w800, color: has ? Colors.white : Colors.white30)),
       if (has) ...[
         const SizedBox(height: 8),
         Text('#${next!.id}   ${clock(next!.timeNs)}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
       ],
       const Spacer(),
       const Text('STANDBY', style: TextStyle(color: kRed, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
       const SizedBox(height: 5),
       FittedBox(
         fit: BoxFit.scaleDown,
         alignment: Alignment.centerLeft,
         child: Text(has ? clock(countdown) : '--:--:--.---', style: TextStyle(fontSize: compact ? 38 : 54, fontWeight: FontWeight.w900, color: has ? kRed : Colors.white24, fontFeatures: const [FontFeature.tabularFigures()])),
       ),
     ]),
   );
 }


 Widget _cueListPanel(bool compact) {
   final activeId=current?.id;
   final nextId=next?.id;
   return Container(
     padding: EdgeInsets.all(compact?12:14),
     decoration:_box(),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[const Text('CUE LIST',style:TextStyle(color:Colors.white70,fontSize:14,fontWeight:FontWeight.w900,letterSpacing:1.3)),const Spacer(),Text('${cueList.length} CUES',style:const TextStyle(color:Colors.white38,fontSize:11,fontWeight:FontWeight.w700))]),
       const SizedBox(height:10),
       Container(height:1,color:kLine),
       const SizedBox(height:6),
       Expanded(child:cueList.isEmpty
         ? const Center(child:Text('NO CUES',style:TextStyle(color:Colors.white24,fontSize:10,fontWeight:FontWeight.w800)))
         : ListView.builder(
             itemCount:cueList.length,
             itemBuilder:(context,i){
               final q=cueList[i];
               final isCurrent=q.id==activeId;
               final isNext=q.id==nextId;
               final past=q.timeNs<pos&&!isCurrent;
               return Container(
                 margin:const EdgeInsets.only(bottom:6),
                 padding:EdgeInsets.symmetric(horizontal:compact?12:14,vertical:compact?11:14),
                 decoration:BoxDecoration(
                   color:isNext?kRed.withValues(alpha:.09):isCurrent?Colors.white.withValues(alpha:.06):Colors.transparent,
                   borderRadius:BorderRadius.circular(8),
                   border:Border.all(color:isNext?kRed.withValues(alpha:.45):isCurrent?Colors.white24:Colors.transparent),
                 ),
                 child:Row(children:[
                   SizedBox(width:38,child:Text('#${q.id}',style:TextStyle(color:isNext?kRed:Colors.white54,fontSize:compact?11:12,fontWeight:FontWeight.w900))),
                   Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                     Text(q.name.isEmpty?'Cue ${q.id}':q.name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:past?Colors.white30:Colors.white,fontSize:compact?13:15,fontWeight:isNext?FontWeight.w900:FontWeight.w700)),
                     const SizedBox(height:2),
                     Row(children:[
                       Text(clock(q.timeNs),style:TextStyle(color:Colors.white54,fontSize:compact?11:12,fontWeight:FontWeight.w600,fontFeatures:const [FontFeature.tabularFigures()])),
                       if(q.department.isNotEmpty)...[const SizedBox(width:7),Flexible(child:Text(q.department.toUpperCase(),overflow:TextOverflow.ellipsis,style:TextStyle(color:isNext?kRed:Colors.white54,fontSize:compact?10:11,fontWeight:FontWeight.w800)))],
                     ]),
                   ])),
                   if(isCurrent)Text('NOW',style:TextStyle(color:Colors.greenAccent,fontSize:compact?10:11,fontWeight:FontWeight.w900)),
                   if(isNext)Text('NEXT',style:TextStyle(color:kRed,fontSize:compact?10:11,fontWeight:FontWeight.w900)),
                 ]),
               );
             },
           )),
     ]),
   );
 }

 Widget _divider() => Container(width: 1, height: 28, color: kLine);
 Widget _statusDot(Color color) => Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
 Widget _miniStatus(String label, String value, Color color) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
   Text(label, style: const TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w700)),
   const SizedBox(height: 2),
   Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
 ]);

 Widget _placeholder() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
   const Icon(Icons.construction_rounded, size: 36, color: Colors.white24),
   const SizedBox(height: 12),
   Text(['SHOW', 'TIMELINE', 'CUES', 'SOURCES', 'SETTINGS'][page], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
   const SizedBox(height: 6),
   const Text('Workspace coming in the next UI iteration', style: TextStyle(color: Colors.white38)),
 ]));

 BoxDecoration _box() => BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine));
 Widget _label(String s) => Text(s, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2));
 Widget _pill(String s, Color color) => Container(
   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
   decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .14))),
   child: Text('●  $s', overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
 );
 Widget _metric(String label, String value, Color color) => Row(children: [
   Expanded(child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9))),
   Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
 ]);

}
