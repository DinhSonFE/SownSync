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
 Widget _show()=>Padding(padding:const EdgeInsets.all(20),child:Column(children:[_hero(),const SizedBox(height:14),Expanded(child:Row(children:[Expanded(flex:7,child:_cueDeck()),const SizedBox(width:14),Expanded(flex:3,child:_rightRail())]))]));
 Widget _hero(){final playing=transport==1,paused=transport==2;final tcColor=playing?Colors.greenAccent:paused?Colors.orangeAccent:kRed;return Container(height:270,padding:const EdgeInsets.fromLTRB(26,20,26,18),decoration:_box(),child:Column(children:[Row(children:[_label('MASTER TIMECODE'),const Spacer(),_pill(playing?'PLAYING':paused?'PAUSED':'STOPPED',tcColor)]),const Spacer(),Text(clock(pos),style:const TextStyle(fontSize:70,fontWeight:FontWeight.w300,letterSpacing:2,fontFeatures:[FontFeature.tabularFigures()])),const SizedBox(height:8),Text('${fps>0?fps.toStringAsFixed(2):'--'} FPS   •   $source MASTER',style:const TextStyle(color:Colors.white38,fontSize:11,letterSpacing:1.2)),const Spacer(),_timeline(),const SizedBox(height:12),Row(children:[Text(clock(pos,millis:false),style:const TextStyle(color:Colors.white38,fontSize:11)),const Spacer(),Text(next!=null?'NEXT  ${clock(countdown)}':'NO UPCOMING CUE',style:TextStyle(color:next!=null?kRed:Colors.white24,fontSize:11,fontWeight:FontWeight.w700))]) ]);}
 Widget _timeline()=>LayoutBuilder(builder:(c,x){return SizedBox(height:34,child:Stack(children:[Positioned(top:16,left:0,right:0,child:Container(height:2,color:kLine)),Positioned(top:8,left:x.maxWidth*.5-1,child:Container(width:2,height:18,color:kRed)),...List.generate(9,(i)=>Positioned(left:x.maxWidth*i/8-0.5,top:13,child:Container(width:1,height:8,color:Colors.white12)))]));});
 Widget _cueDeck()=>Container(padding:const EdgeInsets.all(20),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[_label('SHOW CUES'),const Spacer(),Text('$cueCount CUES',style:const TextStyle(color:Colors.white38,fontSize:10))]),const SizedBox(height:16),Expanded(child:Row(children:[Expanded(child:_cueCard('CURRENT',current,false)),const SizedBox(width:12),Expanded(child:_cueCard('NEXT',next,true))]))]));
 Widget _cueCard(String title,CueView? cue,bool upcoming){return Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:upcoming?kRed.withValues(alpha:.055):Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(12),border:Border.all(color:upcoming&&cue!=null?kRed.withValues(alpha:.42):kLine)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[_label(title),const Spacer(),if(cue!=null)_pill(cue.department.isEmpty?'CUE':cue.department,upcoming?kRed:Colors.white54)]),const Spacer(),Text(cue==null?'—':cue.name,overflow:TextOverflow.ellipsis,maxLines:2,style:TextStyle(fontSize:upcoming?30:26,fontWeight:FontWeight.w700,height:1.05,color:cue==null?Colors.white24:Colors.white)),const SizedBox(height:12),if(cue!=null)Text('#${cue.id}   ${clock(cue.timeNs)}',style:const TextStyle(color:Colors.white38,fontFeatures:[FontFeature.tabularFigures()])),const Spacer(),if(upcoming)Text(cue==null?'READY':'IN  ${clock(countdown)}',style:TextStyle(fontSize:cue==null?13:25,fontWeight:FontWeight.w800,color:cue==null?Colors.white38:kRed,fontFeatures:const [FontFeature.tabularFigures()]))]));}
 Widget _rightRail()=>Column(children:[Expanded(child:_statusPanel()),const SizedBox(height:14),Expanded(child:_sourcePanel())]);
 Widget _statusPanel()=>Container(padding:const EdgeInsets.all(20),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_label('SHOW STATUS'),const Spacer(),_metric('SYNC',locked?'READY':connected?'ACQUIRING':'OFFLINE',locked?Colors.greenAccent:Colors.orangeAccent),const SizedBox(height:18),_metric('TRANSPORT',transport==1?'PLAYING':transport==2?'PAUSED':'STOPPED',transport==1?Colors.greenAccent:transport==2?Colors.orangeAccent:kRed),const SizedBox(height:18),_metric('CUES','$cueCount',Colors.white),const Spacer()]));
 Widget _sourcePanel()=>Container(padding:const EdgeInsets.all(20),decoration:_box(),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_label('TIME SOURCE'),const Spacer(),Row(children:[Container(width:9,height:9,decoration:BoxDecoration(shape:BoxShape.circle,color:connected?Colors.greenAccent:Colors.white24)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(source.isEmpty?'NO SOURCE':source,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),const SizedBox(height:4),Text(connected?'PRIMARY • CONNECTED':'WAITING FOR SOURCE',style:const TextStyle(color:Colors.white38,fontSize:10))]))]),const Spacer(),Text(native?'CORE v0.5.0':'CORE NOT LOADED',style:const TextStyle(color:Colors.white24,fontSize:10))]));
 Widget _placeholder()=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.construction_rounded,size:36,color:Colors.white24),const SizedBox(height:12),Text(['SHOW','TIMELINE','CUES','SOURCES','SETTINGS'][page],style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),const SizedBox(height:6),const Text('Workspace coming in the next UI iteration',style:TextStyle(color:Colors.white38))]));
 BoxDecoration _box()=>BoxDecoration(color:kPanel,borderRadius:BorderRadius.circular(14),border:Border.all(color:kLine));
 Widget _label(String s)=>Text(s,style:const TextStyle(color:Colors.white38,fontSize:10,fontWeight:FontWeight.w800,letterSpacing:1.2));
 Widget _pill(String s,Color c)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:c.withValues(alpha:.1),borderRadius:BorderRadius.circular(20),border:Border.all(color:c.withValues(alpha:.14))),child:Text('●  $s',style:TextStyle(color:c,fontSize:10,fontWeight:FontWeight.w800)));
 Widget _metric(String a,String b,Color c)=>Row(children:[Expanded(child:Text(a,style:const TextStyle(color:Colors.white38,fontSize:10))),Text(b,style:TextStyle(color:c,fontSize:12,fontWeight:FontWeight.w800))]);
}
