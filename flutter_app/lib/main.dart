import 'dart:async';
import 'dart:ffi';
import 'dart:ui' show FontFeature;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

final class NativeState extends Struct {
  @Int32() external int connected;
  @Int32() external int locked;
  @Int32() external int transport;
  @Int64() external int positionNs;
  @Double() external double playbackRate;
  @Double() external double fps;
  @Uint64() external int sequence;
}
typedef InitNative = Int32 Function();
typedef InitDart = int Function();
typedef StateNative = Int32 Function(Pointer<NativeState>);
typedef StateDart = int Function(Pointer<NativeState>);
typedef StringNative = Pointer<Utf8> Function();
typedef StringDart = Pointer<Utf8> Function();

class CoreBridge {
  DynamicLibrary? _lib;
  late InitDart _init;
  late StateDart _state;
  late StringDart _project;
  late StringDart _source;

  bool open() {
    try {
      _lib = DynamicLibrary.open('sown_core_api.dll');
      _init = _lib!.lookupFunction<InitNative, InitDart>('sown_init');
      _state = _lib!.lookupFunction<StateNative, StateDart>('sown_get_state');
      _project = _lib!.lookupFunction<StringNative, StringDart>('sown_get_project_name');
      _source = _lib!.lookupFunction<StringNative, StringDart>('sown_get_active_source');
      return _init() == 1;
    } catch (_) { return false; }
  }
  bool read(Pointer<NativeState> p) => _state(p) == 1;
  String project() => _project().toDartString();
  String source() => _source().toDartString();
}

void main() => runApp(const SownApp());

class SownApp extends StatelessWidget {
  const SownApp({super.key});
  @override Widget build(BuildContext context) {
    const red = Color(0xFFFF334D);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SOWN SYNC',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B0F),
        colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final core = CoreBridge();
  Timer? timer;
  bool nativeLoaded = false, connected = false, locked = false;
  int transport = 0, positionNs = 0;
  String project = 'Waiting for show', source = 'REAPER';

  @override void initState() {
    super.initState();
    nativeLoaded = core.open();
    timer = Timer.periodic(const Duration(milliseconds: 50), (_) => poll());
  }

  void poll() {
    if (!nativeLoaded) return;
    final p = calloc<NativeState>();
    if (core.read(p)) {
      final s = p.ref;
      if (mounted) {
        setState(() {
          connected = s.connected != 0; locked = s.locked != 0;
          transport = s.transport; positionNs = s.positionNs;
          project = core.project(); source = core.source().toUpperCase();
        });
      }
    }
    calloc.free(p);
  }

  @override void dispose() { timer?.cancel(); super.dispose(); }

  String timecode() {
    final ms = positionNs ~/ 1000000;
    final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60, x = ms % 1000;
    String p(int v, int n) => v.toString().padLeft(n, '0');
    return '${p(h,2)}:${p(m,2)}:${p(s,2)}.${p(x,3)}';
  }

  @override Widget build(BuildContext context) {
    const red = Color(0xFFFF334D);
    final transportText = transport == 1 ? 'PLAYING' : transport == 2 ? 'PAUSED' : 'STOPPED';
    final transportColor = transport == 1 ? Colors.greenAccent : transport == 2 ? Colors.orangeAccent : red;
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          backgroundColor: const Color(0xFF0D121A), selectedIndex: 0,
          labelType: NavigationRailLabelType.all,
          indicatorColor: red.withValues(alpha: .18),
          selectedIconTheme: const IconThemeData(color: red),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Show')),
            NavigationRailDestination(icon: Icon(Icons.timeline), label: Text('Timeline')),
            NavigationRailDestination(icon: Icon(Icons.list_alt), label: Text('Cues')),
            NavigationRailDestination(icon: Icon(Icons.cable), label: Text('Connections')),
            NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('Settings')),
          ],
        ),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('SOWN SYNC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              status(connected ? 'CONNECTED' : 'OFFLINE', connected ? Colors.greenAccent : Colors.grey),
            ]),
            const SizedBox(height: 24),
            Text(project.isEmpty ? 'Untitled Show' : project, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('$source  •  ${locked ? 'SYNCED' : connected ? 'CONNECTING' : 'NO SOURCE'}',
              style: TextStyle(color: locked ? Colors.greenAccent : Colors.white54)),
            const SizedBox(height: 28),
            Expanded(flex: 3, child: panel(
              Column(children: [Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(transportText, style: TextStyle(color: transportColor, fontWeight: FontWeight.w700, letterSpacing: 2)),
                const SizedBox(height: 12),
                Text(timecode(), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 20),
                Container(height: 2, color: Colors.white12),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filledTonal(onPressed: null, icon: const Icon(Icons.skip_previous)),
                  const SizedBox(width: 12),
                  IconButton.filled(onPressed: null, icon: Icon(transport == 1 ? Icons.pause : Icons.play_arrow), style: IconButton.styleFrom(backgroundColor: red)),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(onPressed: null, icon: const Icon(Icons.stop)),
                ]),
              ])))]),
            )),
            const SizedBox(height: 16),
            Expanded(flex: 2, child: Row(children: [
              Expanded(child: cueCard('CURRENT CUE', '—', 'Waiting for cue', Colors.white70)),
              const SizedBox(width: 16),
              Expanded(child: cueCard('NEXT CUE', '—', 'Ready', red)),
            ])),
            const SizedBox(height: 16),
            Row(children: [
              chip(Icons.sync, locked ? 'SYNC READY' : 'SYNC WAITING', locked ? Colors.greenAccent : Colors.orangeAccent),
              const SizedBox(width: 10), chip(Icons.graphic_eq, source, Colors.white70),
              const Spacer(),
              Text(nativeLoaded ? 'Core v0.4.0' : 'Core DLL not loaded', style: const TextStyle(color: Colors.white38)),
            ]),
          ]),
        )),
      ]),
    );
  }

  Widget panel(Widget child) => Container(
    decoration: BoxDecoration(color: const Color(0xFF11151C), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
    padding: const EdgeInsets.all(24), child: child,
  );
  Widget cueCard(String a, String b, String d, Color c) => panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(a, style: const TextStyle(color: Colors.white54, fontSize: 12)), const Spacer(),
    Text(b, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)), const SizedBox(height: 8),
    Text(d, style: TextStyle(color: c)), const Spacer(),
  ]));
  Widget chip(IconData i, String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: c), const SizedBox(width: 8), Text(s)]),
  );
  Widget status(String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: c.withValues(alpha: .10), borderRadius: BorderRadius.circular(18)),
    child: Text('●  $s', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
  );
}
