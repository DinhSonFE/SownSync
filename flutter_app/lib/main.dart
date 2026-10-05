import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui' show FontFeature, Size;
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
 @override Widget build(BuildContext context){return Scaffold(body:Row(children:[_nav(),Expanded(child:Column(children:[_top(),Expanded(child:_pageBody())]))]));}
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
         Expanded(child: Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Expanded(flex:5,child:Column(children:[Expanded(flex:5,child:_liveTimeline(compact:compact)),SizedBox(height:compact?8:10),Expanded(flex:4,child:_cueDeck(compact:compact))])),SizedBox(width:compact?8:10),Expanded(flex:3,child:_cueListPanel(compact))])),
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
     height: compact ? 190 : wide ? 235 : 215,
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
         child: Text(clock(pos), style: TextStyle(fontFamily: 'Consolas', fontSize: compact ? 76 : wide ? 116 : 96, fontWeight: FontWeight.w600, color: const Color(0xFFFF4057), letterSpacing: wide ? 6 : 4, fontFeatures: const [FontFeature.tabularFigures()], shadows: const [Shadow(color: Color(0x66FF334D), blurRadius: 16)])),
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
   final syncText = locked ? 'LOCKED' : connected ? 'ACQUIRING' : 'OFFLINE';
   final transportText = transport == 1 ? 'PLAYING' : transport == 2 ? 'PAUSED' : 'STOPPED';
   final transportColor = transport == 1 ? Colors.greenAccent : transport == 2 ? Colors.orangeAccent : kRed;
   return Container(
     height: compact ? 54 : 58,
     padding: const EdgeInsets.symmetric(horizontal: 18),
     decoration: _box(),
     child: Row(children: [
       Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:kRed.withValues(alpha:.12),borderRadius:BorderRadius.circular(7)),child:const Text('RUN',style:TextStyle(color:kRed,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.2))),
       const SizedBox(width:14),
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

 Widget _liveTimeline({bool compact=false}) {
   const windowNs=20000000000;
   final from=pos-windowNs, to=pos+windowNs;
   final visible=cueList.where((q)=>q.timeNs>=from&&q.timeNs<=to).toList();
   return Container(
     padding:EdgeInsets.all(compact?12:16),decoration:_box(),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[_label('LIVE TIMELINE'),const Spacer(),const Text('−20s     NOW     +20s',style:TextStyle(color:Colors.white38,fontSize:10,fontWeight:FontWeight.w700))]),
       const SizedBox(height:8),
       Expanded(child:LayoutBuilder(builder:(context,b){
         final w=b.maxWidth;
         return Stack(clipBehavior:Clip.hardEdge,children:[
           Positioned(left:0,right:0,top:b.maxHeight*.48,child:Container(height:2,color:kLine)),
           ...List.generate(9,(i)=>Positioned(left:(w-1)*i/8,top:b.maxHeight*.48-5,child:Container(width:1,height:10,color:Colors.white12))),
           Positioned(left:w*.5-1,top:0,bottom:0,child:Container(width:2,color:kRed)),
           ...visible.map((q){
             final x=((q.timeNs-from)/(to-from))*w;
             final isPast=q.timeNs<pos, isNext=q.id==next?.id;
             final color=isNext?kRed:(isPast?Colors.white24:Colors.white70);
             return Positioned(left:(x-2).clamp(0.0,w-90),top:isNext?18:42+(q.id%2)*30,child:SizedBox(width:90,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
               Container(width:isNext?3:2,height:isNext?34:22,color:color),const SizedBox(height:3),
               Text(q.name.isEmpty?'Cue '+q.id.toString():q.name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:color,fontSize:isNext?11:9,fontWeight:isNext?FontWeight.w900:FontWeight.w700)),
             ])));
           }),
           Positioned(left:w*.5-44,bottom:0,child:SizedBox(width:88,child:Text(clock(pos,millis:false),textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70,fontSize:10,fontWeight:FontWeight.w800,fontFeatures:[FontFeature.tabularFigures()])))),
         ]);
       })),
     ]),
   );
 }
 Widget _cueDeck({bool compact = false, bool stacked = false}) {
   return Container(
     padding: EdgeInsets.all(compact ? 12 : 16),
     decoration: _box(),
     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [_label('OPERATOR CUES'), const Spacer(), Text('$cueCount CUES', style: const TextStyle(color: Colors.white30, fontSize: 9))]),
       const SizedBox(height: 10),
       Expanded(
         child: stacked
             ? Column(children: [
                 Expanded(child: _currentCard(compact)),
                 const SizedBox(height: 8),
                 Expanded(flex: 2, child: _nextCard(compact)),
               ])
             : Row(children: [
                 Expanded(flex: 4, child: _currentCard(compact)),
                 const SizedBox(width: 10),
                 Expanded(flex: 6, child: _nextCard(compact)),
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
       Row(children:[const Text('CUE STACK',style:TextStyle(color:Colors.white70,fontSize:14,fontWeight:FontWeight.w900,letterSpacing:1.3)),const Spacer(),Text('${cueList.length} CUES',style:const TextStyle(color:Colors.white38,fontSize:11,fontWeight:FontWeight.w700))]),
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


 Widget _pageBody(){switch(page){case 0:return _show();case 1:return _timelinePage();case 2:return _cuesPage();case 3:return _sourcesPage();case 4:return _settingsPage();default:return _show();}}
 Widget _timelinePage(){
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      _sectionHeader('TIMELINE EDITOR','REAPER MARKERS • WAVEFORM • CUSTOM COLORS',
        actions:[_smallButton('+ MARKER'),_smallButton('ZOOM 100%'),_smallButton('FOLLOW',hot:true)]),
      const SizedBox(height:12),
      Expanded(
        child: Container(
          decoration:_box(),
          clipBehavior:Clip.antiAlias,
          child:Column(children:[
            Container(
              height:52,
              padding:const EdgeInsets.symmetric(horizontal:16),
              color:const Color(0xFF0D1118),
              child:Row(children:[
                _filter('ALL MARKERS',Colors.white),
                _filter('LIGHTING',kRed),
                _filter('LASER',Colors.greenAccent),
                _filter('VIDEO',Colors.blueAccent),
                _filter('MACHINE',Colors.orangeAccent),
                _filter('SFX',Colors.purpleAccent),
                const Spacer(),
                const Text('REAPER CUSTOM COLOR SYNC',style:TextStyle(color:Colors.greenAccent,fontSize:10,fontWeight:FontWeight.w800)),
              ]),
            ),
            Expanded(child:CustomPaint(painter:_ReaperTimelinePainter(positionNs:pos),child:const SizedBox.expand())),
          ]),
        ),
      ),
      const SizedBox(height:12),
      Container(
        height:118,
        padding:const EdgeInsets.all(16),
        decoration:_box(),
        child:Row(children:[
          Expanded(flex:2,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _label('MARKER INSPECTOR'),
            const Spacer(),
            const Text('DROP',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
            const Text('Selected REAPER marker',style:TextStyle(color:Colors.white38,fontSize:10)),
          ])),
          Expanded(child:_settingMetric('DEPARTMENT','LIGHTING',kRed)),
          Expanded(child:_settingMetric('TIMECODE','00:00:40.000',Colors.white)),
          Expanded(child:_settingMetric('COLOR','REAPER CUSTOM',Colors.greenAccent)),
        ]),
      ),
    ]),
  );
}
 Widget _cuesPage()=>Padding(padding:const EdgeInsets.all(16),child:Column(children:[_sectionHeader('CUES','CUE DATABASE • FILTER • EDIT • IMPORT',actions:[_smallButton('+ ADD CUE',hot:true)]),const SizedBox(height:12),Expanded(child:Row(children:[Expanded(flex:7,child:Container(padding:const EdgeInsets.all(14),decoration:_box(),child:Column(children:[Row(children:[_filter('ALL',Colors.white),_filter('LIGHTING',kRed),_filter('VIDEO',Colors.blueAccent),_filter('SFX',Colors.orangeAccent),const Spacer(),const SizedBox(width:220,child:TextField(decoration:InputDecoration(isDense:true,hintText:'Search cues…',prefixIcon:Icon(Icons.search,size:18),border:OutlineInputBorder())))]),const SizedBox(height:12),const Divider(height:1,color:kLine),Expanded(child:cueList.isEmpty?const Center(child:Text('NO CUES FROM SOURCE',style:TextStyle(color:Colors.white30))):ListView.builder(itemCount:cueList.length,itemBuilder:(context,i){final q=cueList[i];final col=_deptColor(q.department);return Container(height:62,margin:const EdgeInsets.only(top:6),padding:const EdgeInsets.symmetric(horizontal:12),decoration:BoxDecoration(color:q.id==next?.id?kRed.withValues(alpha:.08):Colors.transparent,borderRadius:BorderRadius.circular(8)),child:Row(children:[Container(width:3,height:30,color:col),const SizedBox(width:12),SizedBox(width:55,child:Text('#'+q.id.toString(),style:const TextStyle(color:Colors.white54,fontWeight:FontWeight.w800))),SizedBox(width:135,child:Text(clock(q.timeNs),style:const TextStyle(fontFeatures:[FontFeature.tabularFigures()],color:Colors.white54))),Expanded(child:Text(q.name.isEmpty?'Cue '+q.id.toString():q.name,style:const TextStyle(fontWeight:FontWeight.w700))),SizedBox(width:120,child:Text(q.department.isEmpty?'ALL':q.department.toUpperCase(),style:TextStyle(color:col,fontSize:10,fontWeight:FontWeight.w800))),Text(q.id==current?.id?'NOW':q.id==next?.id?'NEXT':'READY',style:TextStyle(color:q.id==current?.id?Colors.greenAccent:q.id==next?.id?kRed:Colors.white30,fontSize:10,fontWeight:FontWeight.w900))]));}))]))),const SizedBox(width:12),Expanded(flex:3,child:Container(padding:const EdgeInsets.all(18),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('CUE EDITOR',style:TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:24),_editField('NAME',next?.name??'DROP'),_editField('DEPARTMENT',next?.department??'LIGHTING'),_editField('TIMECODE',next==null?'00:00:40.000':clock(next!.timeNs)),_editField('WARNING','00:00:05.000'),_editField('SOURCE',source),const Spacer(),SizedBox(width:double.infinity,child:FilledButton(style:FilledButton.styleFrom(backgroundColor:kRed),onPressed:(){},child:const Text('SAVE CHANGES')))])))]))]));
 Widget _sourcesPage()=>Padding(padding:const EdgeInsets.all(16),child:Column(children:[_sectionHeader('SOURCES & SYNC','INPUT SOURCES • CLOCK • HEALTH • FAILOVER'),const SizedBox(height:12),Expanded(child:Row(children:[Expanded(flex:2,child:Container(padding:const EdgeInsets.all(16),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_label('SYNC SOURCES'),const SizedBox(height:14),_sourceCard('REAPER','PRIMARY',connected?'CONNECTED':'OFFLINE',connected?Colors.greenAccent:Colors.white38,true),_sourceCard('LTC','BACKUP','NO SIGNAL',Colors.white38,false),_sourceCard('MTC','AVAILABLE','IDLE',Colors.white38,false),_sourceCard('CUEPOINTS','AVAILABLE','DISCONNECTED',Colors.white38,false)]))),const SizedBox(width:12),Expanded(child:Column(children:[Expanded(child:Container(padding:const EdgeInsets.all(18),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_label('SYNC HEALTH'),const SizedBox(height:20),Text(locked?'LOCKED':connected?'ACQUIRING':'OFFLINE',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,color:locked?Colors.greenAccent:kRed)),const SizedBox(height:24),_metric('SOURCE',source,Colors.white),const SizedBox(height:16),_metric('FPS',fps>0?fps.toStringAsFixed(2):'--',Colors.white),const SizedBox(height:16),_metric('TRANSPORT',transport==1?'PLAYING':transport==2?'PAUSED':'STOPPED',transport==1?Colors.greenAccent:kRed)]))),const SizedBox(height:12),Expanded(child:Container(padding:const EdgeInsets.all(18),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_label('SOURCE PRIORITY'),const SizedBox(height:14),...['1   REAPER','2   LTC','3   MTC','4   INTERNAL'].map((e)=>Container(height:48,margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.symmetric(horizontal:14),alignment:Alignment.centerLeft,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(8),border:Border.all(color:kLine)),child:Text(e,style:const TextStyle(fontWeight:FontWeight.w700))))]))])))]))]));
 Widget _settingsPage(){
  final sections=['GENERAL','DISPLAY','REAPER','NETWORK','CUE BEHAVIOR','ABOUT'];
  return Padding(
    padding:const EdgeInsets.all(16),
    child:Column(children:[
      _sectionHeader('SETTINGS','APPLICATION • DISPLAY • REAPER • NETWORK'),
      const SizedBox(height:12),
      Expanded(child:Row(children:[
        Container(
          width:280,padding:const EdgeInsets.all(14),decoration:_box(),
          child:Column(children:sections.map((e)=>Container(
            height:48,margin:const EdgeInsets.only(bottom:6),
            padding:const EdgeInsets.symmetric(horizontal:14),alignment:Alignment.centerLeft,
            decoration:BoxDecoration(color:e=='REAPER'?kRed.withValues(alpha:.10):Colors.transparent,borderRadius:BorderRadius.circular(8)),
            child:Text(e,style:TextStyle(color:e=='REAPER'?kRed:Colors.white54,fontSize:11,fontWeight:FontWeight.w800)),
          )).toList()),
        ),
        const SizedBox(width:12),
        Expanded(child:Container(
          padding:const EdgeInsets.all(22),decoration:_box(),
          child:ListView(children:[
            const Text('REAPER INTEGRATION',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
            const SizedBox(height:6),
            const Text('Configure project sync, markers, departments and waveform.',style:TextStyle(color:Colors.white38)),
            const SizedBox(height:28),
            _settingsTitle('CONNECTION'),_settingsRow('Bridge Port','49731'),_settingsRow('Update Rate','30 Hz'),
            const SizedBox(height:22),
            _settingsTitle('MARKER SYNC'),_toggleRow('Sync marker name',true),_toggleRow('Sync marker color',true),_toggleRow('Sync marker position',true),
            const SizedBox(height:22),
            _settingsTitle('DEPARTMENT MAPPING'),_colorRow('LIGHTING','Red marker / LX',kRed),_colorRow('VIDEO','Blue marker / VX',Colors.blueAccent),_colorRow('SFX','Yellow marker / SFX',Colors.orangeAccent),
            const SizedBox(height:22),
            _settingsTitle('WAVEFORM'),_settingsRow('Waveform cache','Enabled'),_settingsRow('Audio source','REAPER master output'),
          ]),
        )),
      ])),
    ]),
  );
}
 Widget _sectionHeader(String title,String sub,{List<Widget> actions=const[]})=>Container(height:68,padding:const EdgeInsets.symmetric(horizontal:18),decoration:_box(),child:Row(children:[Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text(sub,style:const TextStyle(color:Colors.white38,fontSize:9,fontWeight:FontWeight.w700))]),const Spacer(),...actions.map((w)=>Padding(padding:const EdgeInsets.only(left:8),child:w))]));
 Widget _smallButton(String s,{bool hot=false})=>Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:BoxDecoration(color:(hot?kRed:Colors.white).withValues(alpha:hot ? .12 : .04),borderRadius:BorderRadius.circular(7),border:Border.all(color:hot?kRed.withValues(alpha:.3):kLine)),child:Text(s,style:TextStyle(color:hot?kRed:Colors.white70,fontSize:10,fontWeight:FontWeight.w800)));
 Widget _filter(String s,Color c)=>Container(margin:const EdgeInsets.only(right:8),padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),decoration:BoxDecoration(color:c.withValues(alpha:.08),borderRadius:BorderRadius.circular(16)),child:Text(s,style:TextStyle(color:c,fontSize:9,fontWeight:FontWeight.w800)));
 Color _deptColor(String d){final x=d.toUpperCase();if(x.contains('LIGHT')||x=='LX')return kRed;if(x.contains('VIDEO')||x=='VX')return Colors.blueAccent;if(x.contains('SFX'))return Colors.orangeAccent;if(x.contains('LASER'))return Colors.greenAccent;return Colors.white54;}
 Widget _settingMetric(String a,String b,Color c)=>Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text(a,style:const TextStyle(color:Colors.white30,fontSize:9,fontWeight:FontWeight.w800)),const SizedBox(height:8),Text(b,style:TextStyle(color:c,fontSize:12,fontWeight:FontWeight.w800))]);
 Widget _editField(String a,String b)=>Padding(padding:const EdgeInsets.only(bottom:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(color:Colors.white30,fontSize:9,fontWeight:FontWeight.w800)),const SizedBox(height:6),Container(height:42,padding:const EdgeInsets.symmetric(horizontal:12),alignment:Alignment.centerLeft,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(7),border:Border.all(color:kLine)),child:Text(b,overflow:TextOverflow.ellipsis))]));
 Widget _sourceCard(String a,String b,String c,Color col,bool active)=>Container(height:104,margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(10),border:Border.all(color:active?Colors.greenAccent.withValues(alpha:.25):kLine)),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),const SizedBox(height:7),Text(b,style:TextStyle(color:active?kRed:Colors.white30,fontSize:9,fontWeight:FontWeight.w800))])),Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(c,style:TextStyle(color:col,fontSize:10,fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(active?'ACTIVE':'ENABLE',style:TextStyle(color:active?Colors.greenAccent:Colors.white30,fontSize:9,fontWeight:FontWeight.w800))])]));
 Widget _settingsTitle(String s)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Container(padding:const EdgeInsets.only(bottom:9),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:kLine))),child:Align(alignment:Alignment.centerLeft,child:Text(s,style:const TextStyle(color:Colors.white54,fontSize:10,fontWeight:FontWeight.w900)))));
 Widget _settingsRow(String a,String b)=>Container(height:52,alignment:Alignment.center,child:Row(children:[Expanded(child:Text(a,style:const TextStyle(fontWeight:FontWeight.w600))),Text(b,style:const TextStyle(color:Colors.white54,fontWeight:FontWeight.w700))]));
 Widget _toggleRow(String a,bool on)=>Container(height:48,alignment:Alignment.center,child:Row(children:[Expanded(child:Text(a)),Container(width:48,height:26,decoration:BoxDecoration(color:(on?Colors.greenAccent:Colors.white24).withValues(alpha:.16),borderRadius:BorderRadius.circular(20)),alignment:on?Alignment.centerRight:Alignment.centerLeft,padding:const EdgeInsets.all(3),child:Container(width:20,height:20,decoration:BoxDecoration(color:on?Colors.greenAccent:Colors.white38,shape:BoxShape.circle)))]));
 Widget _colorRow(String a,String b,Color c)=>Container(height:48,alignment:Alignment.center,child:Row(children:[Container(width:4,height:24,color:c),const SizedBox(width:12),SizedBox(width:140,child:Text(a,style:TextStyle(color:c,fontSize:10,fontWeight:FontWeight.w900))),Text(b,style:const TextStyle(color:Colors.white54,fontSize:10))]));

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

class _ReaperTimelinePainter extends CustomPainter{
 final int positionNs;_ReaperTimelinePainter({required this.positionNs});
 @override void paint(Canvas canvas,Size size){
  canvas.drawRect(Offset.zero&size,Paint()..color=const Color(0xFF0B0E18));
  for(var i=0;i<12;i++){final y=70+i*(size.height-70)/12;canvas.drawLine(Offset(0,y),Offset(size.width,y),Paint()..color=const Color(0xFF252B35));}
  for(var i=0;i<32;i++){final x=i*size.width/32;canvas.drawLine(Offset(x,0),Offset(x,size.height),Paint()..color=const Color(0x33252B35));}
  const cols=[Color(0xFFB45CFF),Color(0xFFFF334D),Color(0xFF35D27F),Color(0xFF35D27F),Color(0xFF5B6DFF),Color(0xFFF6A623),Color(0xFFE55AEF),Color(0xFFC9CBD0),Color(0xFFB99A85),Color(0xFF35D27F),Color(0xFF35D27F),Color(0xFF35D27F),Color(0xFF35D27F),Color(0xFFFF334D)];
  const xs=[.03,.08,.15,.18,.22,.27,.31,.35,.39,.47,.55,.60,.74,.90];
  final wave=Paint()..color=const Color(0xAA35D27F)..strokeWidth=2;
  for(var b=0;b<3;b++){final cy=size.height*(.34+b*.22);final amp=size.height*(b==2 ? .12 : .075);for(var i=0;i<size.width.toInt();i+=4){final v=(.25+.75*(i%97)/97.0)*(0.5+0.5*((i*13+b*29)%41)/41.0);canvas.drawLine(Offset(i.toDouble(),cy-amp*v),Offset(i.toDouble(),cy+amp*v),wave);}}
  for(var i=0;i<xs.length;i++){final x=size.width*xs[i],p=Paint()..color=cols[i]..strokeWidth=2;canvas.drawLine(Offset(x,52),Offset(x,size.height),p);canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center:Offset(x,38),width:24,height:22),const Radius.circular(4)),p);final tp=TextPainter(text:TextSpan(text:(i<9?i+2:i-8).toString(),style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w800)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(x-tp.width/2,38-tp.height/2));}
  final px=size.width*.82;canvas.drawLine(Offset(px,0),Offset(px,size.height),Paint()..color=kRed..strokeWidth=3);
  final t=TextPainter(text:const TextSpan(text:'▼',style:TextStyle(color:kRed,fontSize:20)),textDirection:TextDirection.ltr)..layout();t.paint(canvas,Offset(px-t.width/2,-4));
  const labels=['00:00:12','00:00:18','00:00:24','00:00:30','00:00:36'];for(var i=0;i<labels.length;i++){final tp=TextPainter(text:TextSpan(text:labels[i],style:const TextStyle(color:Colors.white38,fontSize:9)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(12+i*(size.width-100)/4,8));}
 }
 @override bool shouldRepaint(covariant _ReaperTimelinePainter old)=>old.positionNs!=positionNs;
}
