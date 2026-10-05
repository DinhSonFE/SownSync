import 'dart:async';
import 'dart:ffi';
import 'dart:ui' show FontFeature;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

final class NativeState extends Struct {
  @Int32() external int connected; @Int32() external int locked; @Int32() external int transport;
  @Int64() external int positionNs; @Double() external double playbackRate; @Double() external double fps; @Uint64() external int sequence;
}
typedef InitN=Int32 Function(); typedef InitD=int Function();
typedef StateN=Int32 Function(Pointer<NativeState>); typedef StateD=int Function(Pointer<NativeState>);
typedef StrN=Pointer<Utf8> Function(); typedef StrD=Pointer<Utf8> Function();

class Core {
  DynamicLibrary? lib; late InitD init; late StateD state; late StrD project; late StrD source;
  bool open(){
    try{lib=DynamicLibrary.open('sown_core_api.dll');init=lib!.lookupFunction<InitN,InitD>('sown_init');state=lib!.lookupFunction<StateN,StateD>('sown_get_state');project=lib!.lookupFunction<StrN,StrD>('sown_get_project_name');source=lib!.lookupFunction<StrN,StrD>('sown_get_active_source');return init()==1;}catch(_){return false;}
  }
}
void main()=>runApp(const SownApp());
class SownApp extends StatelessWidget{const SownApp({super.key});@override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'SOWN SYNC',theme:ThemeData.dark(useMaterial3:true).copyWith(scaffoldBackgroundColor:const Color(0xff090b0f),colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xffff334d),brightness:Brightness.dark)),home:const Home());}
class Home extends StatefulWidget{const Home({super.key});@override State<Home> createState()=>_Home();}
class _Home extends State<Home>{
 final core=Core(); Timer? timer; bool native=false,connected=false,locked=false;int transport=0,pos=0;String project='Waiting for show',source='REAPER';
 @override void initState(){super.initState();native=core.open();timer=Timer.periodic(const Duration(milliseconds:50),(_)=>poll());}
 void poll(){if(!native)return;final p=calloc<NativeState>();if(core.state(p)==1){final s=p.ref;setState((){connected=s.connected!=0;locked=s.locked!=0;transport=s.transport;pos=s.positionNs;project=core.project().toDartString();source=core.source().toDartString().toUpperCase();});}calloc.free(p);}
 @override void dispose(){timer?.cancel();super.dispose();}
 String tc(){var ms=pos~/1000000,h=ms~/3600000,m=(ms~/60000)%60,s=(ms~/1000)%60,x=ms%1000;return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}.${x.toString().padLeft(3,'0')}';}
 @override Widget build(BuildContext c){final red=const Color(0xffff334d);return Scaffold(body:Row(children:[
  NavigationRail(backgroundColor:const Color(0xff0d121a),selectedIndex:0,labelType:NavigationRailLabelType.all,indicatorColor:red.withOpacity(.18),selectedIconTheme:IconThemeData(color:red),destinations:const[
   NavigationRailDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:Text('Show')),
   NavigationRailDestination(icon:Icon(Icons.timeline),label:Text('Timeline')),NavigationRailDestination(icon:Icon(Icons.list_alt),label:Text('Cues')),
   NavigationRailDestination(icon:Icon(Icons.cable),label:Text('Connections')),NavigationRailDestination(icon:Icon(Icons.settings_outlined),label:Text('Settings'))]),
  Expanded(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[const Text('SOWN SYNC',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const Spacer(),_status(connected?'CONNECTED':'OFFLINE',connected?Colors.greenAccent:Colors.grey)]),
   const SizedBox(height:24),Text(project.isEmpty?'Untitled Show':project,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),const SizedBox(height:6),Text('$source  •  ${locked?'SYNCED':connected?'CONNECTING':'NO SOURCE'}',style:TextStyle(color:locked?Colors.greenAccent:Colors.white54)),
   const SizedBox(height:28),Expanded(flex:3,child:_panel(Column(children:[Expanded(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Text(transport==1?'PLAYING':transport==2?'PAUSED':'STOPPED',style:TextStyle(color:transport==1?Colors.greenAccent:red,fontWeight:FontWeight.w700,letterSpacing:2)),
    const SizedBox(height:12),Text(tc(),style:const TextStyle(fontSize:64,fontWeight:FontWeight.w300,fontFeatures:[FontFeature.tabularFigures()])),
    const SizedBox(height:20),Container(height:2,color:Colors.white12),const SizedBox(height:18),
    Row(mainAxisAlignment:MainAxisAlignment.center,children:[IconButton.filledTonal(onPressed:null,icon:const Icon(Icons.skip_previous)),const SizedBox(width:12),IconButton.filled(onPressed:null,icon:Icon(transport==1?Icons.pause:Icons.play_arrow),style:IconButton.styleFrom(backgroundColor:red)),const SizedBox(width:12),IconButton.filledTonal(onPressed:null,icon:const Icon(Icons.stop))])
   ]))]))),
   const SizedBox(height:16),Expanded(flex:2,child:Row(children:[Expanded(child:_cue('CURRENT CUE','—','Waiting for cue',Colors.white70)),const SizedBox(width:16),Expanded(child:_cue('NEXT CUE','—','Ready',red))])),
   const SizedBox(height:16),Row(children:[_chip(Icons.sync,locked?'SYNC READY':'SYNC WAITING',locked?Colors.greenAccent:Colors.orangeAccent),const SizedBox(width:10),_chip(Icons.graphic_eq,source,Colors.white70),const Spacer(),Text(native?'Core v0.4.0':'Core DLL not loaded',style:const TextStyle(color:Colors.white38))])
  ])))
 ]));}
 Widget _panel(Widget child)=>Container(decoration:BoxDecoration(color:const Color(0xff11151c),borderRadius:BorderRadius.circular(16),border:Border.all(color:Colors.white10)),padding:const EdgeInsets.all(24),child:child);
 Widget _cue(String a,String b,String d,Color c)=>_panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(color:Colors.white54,fontSize:12)),const Spacer(),Text(b,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w700)),const SizedBox(height:8),Text(d,style:TextStyle(color:c)),const Spacer()]));
 Widget _chip(IconData i,String s,Color c)=>Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:9),decoration:BoxDecoration(color:Colors.white.withOpacity(.04),borderRadius:BorderRadius.circular(20)),child:Row(children:[Icon(i,size:16,color:c),const SizedBox(width:8),Text(s)]));
 Widget _status(String s,Color c)=>Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),decoration:BoxDecoration(color:c.withOpacity(.1),borderRadius:BorderRadius.circular(18)),child:Text('●  $s',style:TextStyle(color:c,fontSize:12,fontWeight:FontWeight.w700)));
}
