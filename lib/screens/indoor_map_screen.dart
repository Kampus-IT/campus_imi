// lib/screens/indoor_map_screen.dart
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ ИМПОРТ
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

import '../models/lesson.dart';
import '../services/cache_service.dart';
import '../utils/building_resolver.dart';
import '../utils/hardcoded_departments.dart';
import '../utils/room_index.dart';
import 'map_data.dart';
import 'map_style.dart';

// ───────────────────────── Модели ─────────────────────────
class RoomShape {
  final String number;
  final Path path;
  RoomShape(this.number, this.path);
  Offset get center => path.getBounds().center;
}

class MapLabel {
  final String text;
  final Offset pos;
  final double rotation;
  MapLabel(this.text, this.pos, this.rotation);
}

class FloorPlan {
  final Size size;
  final List<RoomShape> rooms;
  final List<MapLabel> labels;
  final String svg;
  FloorPlan(this.size, this.rooms, this.labels, this.svg);

  RoomShape? roomAt(Offset p) {
    for (final r in rooms) {
      if (r.path.contains(p)) return r;
    }
    return null;
  }

  RoomShape? byNumber(String n) {
    for (final r in rooms) {
      if (r.number == n) return r;
    }
    return null;
  }
}

class RoomInfo {
  final String title;
  final String description;
  final String department;
  RoomInfo({required this.title, this.description = '', this.department = ''});
}

class Suggestion {
  final String label;
  final String subtitle;
  final String room;
  final bool isTeacher;
  Suggestion(this.label, this.subtitle, this.room, {this.isTeacher = false});
}

// ───────────────────────── Загрузка SVG ─────────────────────────
Future<FloorPlan> loadFloorPlan(String asset) async {
  final raw = await rootBundle.loadString(asset);
  final doc = XmlDocument.parse(raw);
  final svg = doc.rootElement;

  double minX = 0, minY = 0, w = 1000, h = 1000;
  final vb = svg.getAttribute('viewBox');
  if (vb != null) {
    final v = vb.trim().split(RegExp(r'[ ,]+')).map(double.parse).toList();
    if (v.length == 4) {
      minX = v[0];
      minY = v[1];
      w = v[2];
      h = v[3];
    }
  } else {
    w = double.tryParse(svg.getAttribute('width') ?? '') ?? w;
    h = double.tryParse(svg.getAttribute('height') ?? '') ?? h;
  }

  final rooms = <RoomShape>[];
  for (final el in doc.descendants.whereType<XmlElement>()) {
    final id = el.getAttribute('id');
    if (id == null || !id.startsWith('room-')) continue;

    Path? p;
    switch (el.name.local) {
      case 'path':
        p = parseSvgPathData(el.getAttribute('d') ?? '');
        break;
      case 'rect':
        final x = double.tryParse(el.getAttribute('x') ?? '0') ?? 0;
        final y = double.tryParse(el.getAttribute('y') ?? '0') ?? 0;
        final rw = double.tryParse(el.getAttribute('width') ?? '0') ?? 0;
        final rh = double.tryParse(el.getAttribute('height') ?? '0') ?? 0;
        p = Path()..addRect(Rect.fromLTWH(x, y, rw, rh));
        break;
      case 'polygon':
        final pts = (el.getAttribute('points') ?? '')
            .trim()
            .split(RegExp(r'[ ,]+'))
            .map(double.parse)
            .toList();
        p = Path();
        for (var i = 0; i + 1 < pts.length; i += 2) {
          i == 0 ? p.moveTo(pts[i], pts[i + 1]) : p.lineTo(pts[i], pts[i + 1]);
        }
        p.close();
        break;
    }
    if (p != null) {
      rooms.add(RoomShape(id.substring(5), p.shift(Offset(-minX, -minY))));
    }
  }

  final labels = <MapLabel>[];
  final lg = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'g' && e.getAttribute('id') == 'labels')
      .toList();
  for (final g in lg) {
    for (final t in g.findElements('text')) {
      final x = double.tryParse(t.getAttribute('x') ?? '') ?? 0;
      final y = double.tryParse(t.getAttribute('y') ?? '') ?? 0;
      var rot = 0.0;
      final tr = t.getAttribute('transform');
      if (tr != null) {
        final m = RegExp(r'rotate\(\s*(-?[\d.]+)').firstMatch(tr);
        if (m != null) rot = double.parse(m.group(1)!) * 3.1415926535 / 180;
      }
      labels.add(MapLabel(t.innerText.trim(), Offset(x - minX, y - minY), rot));
    }
    g.parent!.children.remove(g);
  }
  return FloorPlan(Size(w, h), rooms, labels, doc.toXmlString());
}

// ───────────────────────── Граф навигации ─────────────────────────
class NavGraph {
  final Map<String, Offset> nodes = {};
  final Map<String, List<MapEntry<String, double>>> _adj = {};

  NavGraph._();

  static Future<NavGraph?> load(String asset) async {
    try {
      final j = jsonDecode(await rootBundle.loadString(asset));
      final g = NavGraph._();
      (j['nodes'] as Map<String, dynamic>).forEach((k, v) {
        g.nodes[k] = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      });
      for (final e in j['edges'] as List) {
        final a = e[0] as String, b = e[1] as String;
        final d = (g.nodes[a]! - g.nodes[b]!).distance;
        g._adj.putIfAbsent(a, () => []).add(MapEntry(b, d));
        g._adj.putIfAbsent(b, () => []).add(MapEntry(a, d));
      }
      return g;
    } catch (_) {
      return null;
    }
  }

  bool has(String id) => nodes.containsKey(id);

  (Map<String, double>, Map<String, String>) _dijkstra(String src) {
    final dist = <String, double>{for (final k in nodes.keys) k: double.infinity};
    final prev = <String, String>{};
    final todo = nodes.keys.toSet();
    dist[src] = 0;
    while (todo.isNotEmpty) {
      String? u;
      for (final k in todo) {
        if (u == null || dist[k]! < dist[u]!) u = k;
      }
      if (u == null || dist[u]! == double.infinity) break;
      todo.remove(u);
      for (final e in _adj[u] ?? const <MapEntry<String, double>>[]) {
        final nd = dist[u]! + e.value;
        if (nd < dist[e.key]!) {
          dist[e.key] = nd;
          prev[e.key] = u;
        }
      }
    }
    return (dist, prev);
  }

  List<Offset>? route(String from, String to) {
    if (!has(from) || !has(to)) return null;
    final (dist, prev) = _dijkstra(from);
    if (dist[to]! == double.infinity) return null;
    return _build(prev, from, to);
  }

  List<Offset>? routeFromNearestStairs(String to) {
    if (!has(to)) return null;
    final (dist, prev) = _dijkstra(to);
    String? best;
    for (final k in nodes.keys) {
      if ((k.startsWith('stairs-') || k.startsWith('exit-')) && dist[k]! < double.infinity) {
        if (best == null || dist[k]! < dist[best]!) best = k;
      }
    }
    if (best == null) return null;
    return _build(prev, to, best).reversed.toList();
  }

  List<Offset> _build(Map<String, String> prev, String from, String to) {
    final out = <Offset>[];
    String? cur = to;
    while (cur != null) {
      out.add(nodes[cur]!);
      if (cur == from) break;
      cur = prev[cur];
    }
    return out.reversed.toList();
  }
}

// ───────────────────────── Помощники ─────────────────────────
String? normRoom(String raw) {
  final m = RegExp(r'(\d{1,4})\s*[-]?\s*([а-яА-Яa-zA-Z]?)').firstMatch(raw);
  if (m == null) return null;
  var suffix = (m.group(2) ?? '').toLowerCase();
  if (suffix == 'а') suffix = 'a';
  return '${m.group(1)}$suffix';
}

int? floorOfRoom(String room) {
  final m = RegExp(r'^(\d+)').firstMatch(room);
  if (m == null) return null;
  final digits = m.group(1)!;

  if (digits.length <= 2) return int.tryParse(digits);

  if (digits.length == 4) {
    return int.tryParse(digits.substring(0, 2));
  }
  return int.tryParse(digits[0]);
}

const _dayNames = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

// ───────────────────────── Экран ─────────────────────────
class IndoorMapScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;
  final List<int> floors;
  final String? initialRoom;

  final VoidCallback? onBack;
  final void Function(MapBuilding)? onBuildingSelected;

  const IndoorMapScreen({
    super.key,
    this.buildingId = 'ammosov',
    this.buildingName = 'Учебный корпус СВФУ',
    this.floors = const [1, 2, 3, 4, 5, 6, 7],
    this.initialRoom,
    this.onBack,
    this.onBuildingSelected,
  });

  static Future<void> openForRoom(BuildContext context, String rawRoom, {String? building}) async {
    final room = normRoom(rawRoom) ?? rawRoom.trim();
    if (room.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось определить номер кабинета')));
      return;
    }
    final idx = await RoomIndex.load();
    final blocks = idx.blocksFor(room, building: building, text: rawRoom);
    if (!context.mounted) return;
    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Кабинета $room нет на картах')));
      return;
    }
    MapBuilding? pick = blocks.length == 1 ? blocks.first : null;
    pick ??= await showModalBottomSheet<MapBuilding>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('В каком корпусе кабинет?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ),
            for (final b in blocks)
              ListTile(title: Text(b.name), subtitle: Text(b.address), onTap: () => Navigator.pop(ctx, b)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == null || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => IndoorMapScreen(buildingId: pick!.id, buildingName: pick!.name, floors: pick!.floors, initialRoom: room)));
  }

  @override
  State<IndoorMapScreen> createState() => _IndoorMapScreenState();
}

class _IndoorMapScreenState extends State<IndoorMapScreen> {
  final _transform = TransformationController();
  final Map<int, FloorPlan> _plans = {};
  final Map<int, NavGraph?> _graphs = {};
  List<Lesson> _lessons = [];

  int _floor = 4;
  FloorPlan? _plan;
  RoomShape? _selected;
  RoomInfo? _info;
  List<Offset>? _route;
  String? _routeStart;
  Size _viewport = Size.zero;
  double _fitScale = 0.5;
  bool _loading = true;
  String? _error;

  String _asset(int f) => 'assets/maps/${widget.buildingId}_f$f.svg';
  String _navAsset(int f) => 'assets/maps/${widget.buildingId}_f${f}_nav.json';

  @override
  void initState() {
    super.initState();
    _floor = widget.floors.first;
    _init();
  }

  Future<void> _init() async {
    _loadLessons();
    await _setFloor(_floor);
    if (widget.initialRoom != null) {
      await _findRoom(widget.initialRoom!);
    }
  }

  // ✅ ОПТИМИЗИРОВАННЫЙ МЕТОД (без чтения всей базы)
  Future<void> _loadLessons() async {
    if (FirebaseAuth.instance.currentUser == null) {
      final cached = await CacheService.loadMapLessons();
      if (mounted) setState(() => _lessons = cached);
      return;
    }
    try {
      final current = widget.buildingId;

      // 1. Пытаемся взять пары из кэша
      final cached = await CacheService.loadMapLessons();
      if (cached.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _lessons = cached;
        });
        final isFresh = await CacheService.isMapFresh();
        if (isFresh) return; // Если кэш свежий — не идем в сеть
      }

      // 2. Идем в сеть, но с ФИЛЬТРОМ по корпусу
      final snap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('building', isEqualTo: current) // ✅ Фильтр на сервере
          .get();

      final all = snap.docs.map((d) => Lesson.fromMap(d.id, d.data())).toList();

      // 3. Для старых пар без building — фильтруем локально
      final groupsSnap = await FirebaseFirestore.instance.collection('groups').get();
      final Map<String, String> groupToInstitute = {};
      for (final doc in groupsSnap.docs) {
        final name = doc.data()['name']?.toString() ?? doc.id;
        final institute = doc.data()['institute']?.toString() ?? '';
        if (name.isNotEmpty) groupToInstitute[name] = institute;
      }

      final filtered = all.where((l) {
        if (l.time.isEmpty || l.time.startsWith('00:00') || l.time == '-') return false;
        if (l.building.isNotEmpty) {
          if (current.startsWith('guk')) return l.building == 'guk';
          return l.building == current;
        }
        final institute = groupToInstitute[l.group] ?? '';
        final defaultBuilding = getBuildingForInstitute(institute);
        if (defaultBuilding.isEmpty) return false;
        if (current.startsWith('guk')) return defaultBuilding == 'guk';
        return defaultBuilding == current;
      }).toList();

      // 4. Сохраняем в кэш и обновляем UI
      await CacheService.saveMapLessons(filtered);
      if (mounted) {
        setState(() {
          _lessons = filtered;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки пар для карты: $e');
    }
  }

  Future<FloorPlan?> _getPlan(int f) async {
    if (_plans.containsKey(f)) return _plans[f];
    try {
      return _plans[f] = await loadFloorPlan(_asset(f));
    } catch (_) {
      return null;
    }
  }

  Future<NavGraph?> _getGraph(int f) async {
    if (_graphs.containsKey(f)) return _graphs[f];
    return _graphs[f] = await NavGraph.load(_navAsset(f));
  }

  Future<void> _setFloor(int f) async {
    setState(() => _loading = true);
    final plan = await _getPlan(f);
    if (!mounted) return;
    setState(() {
      _floor = f;
      _plan = plan;
      _error = plan == null ? 'План $f этажа пока не загружен' : null;
      _selected = null;
      _info = null;
      _route = null;
      _routeStart = null;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
  }

  void _fitToScreen() {
    if (_plan == null || _viewport == Size.zero) return;
    final s = (_viewport.width / _plan!.size.width).clamp(0.0, _viewport.height / _plan!.size.height);
    _fitScale = s;
    final dx = (_viewport.width - _plan!.size.width * s) / 2;
    final dy = (_viewport.height - _plan!.size.height * s) / 2;
    _transform.value = Matrix4.identity()..translate(dx, dy)..scale(s);
  }

  void _centerOn(Offset c, {double? scale}) {
    final s = scale ?? (_fitScale * 3.2);
    _transform.value = Matrix4.identity()..translate(_viewport.width / 2, _viewport.height / 2)..scale(s)..translate(-c.dx, -c.dy);
  }

  void _fitBounds(Rect r) {
    const pad = 80.0;
    final s = ((_viewport.width) / (r.width + pad * 2)).clamp(0.0, (_viewport.height * 0.6) / (r.height + pad * 2)).clamp(_fitScale, 4.0);
    _centerOn(r.center, scale: s);
  }

  Future<void> _onTapRoom(RoomShape? r) async {
    if (_routeStart != null && r != null && r.number != _routeStart) {
      await _buildRoute(_routeStart!, r.number);
      return;
    }
    await _select(r);
  }

  Future<void> _select(RoomShape? r) async {
    setState(() {
      _selected = r;
      _info = null;
      if (r != null) _route = null;
    });
    if (r == null) return;
    try {
      final d = await FirebaseFirestore.instance.collection('buildings').doc(widget.buildingId).collection('rooms').doc(r.number).get();
      if (!mounted || _selected != r) return;
      final m = d.data();
      setState(() => _info = RoomInfo(title: m?['title'] ?? 'Аудитория ${r.number}', description: m?['description'] ?? '', department: m?['department'] ?? ''));
    } catch (_) {
      if (mounted) setState(() => _info = RoomInfo(title: 'Аудитория ${r.number}'));
    }
  }

  Future<void> _findRoom(String raw) async {
    final number = normRoom(raw) ?? raw.trim();
    if (number.isEmpty) return;

    final guess = floorOfRoom(number);
    final order = <int>{ if (guess != null && widget.floors.contains(guess)) guess, _floor, ...widget.floors };

    for (final f in order) {
      final plan = await _getPlan(f);
      final room = plan?.byNumber(number);
      if (room != null) {
        if (f != _floor) await _setFloor(f);
        await _select(room);
        _centerOn(room.center);
        return;
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Кабинет $number не найден')));
  }

  Future<void> _buildRoute(String from, String to) async {
    final g = await _getGraph(_floor);
    final plan = _plan;
    if (g == null || plan == null) return _toast('Для этого этажа ещё нет графа маршрутов');
    final path = g.route(from, to);
    if (path == null) return _toast('Маршрут между $from и $to пока недоступен');
    _applyRoute([
      if (plan.byNumber(from) != null) plan.byNumber(from)!.center,
      ...path,
      if (plan.byNumber(to) != null) plan.byNumber(to)!.center,
    ]);
    final target = plan.byNumber(to);
    setState(() { _routeStart = null; _selected = target; });
  }

  Future<void> _routeFromStairs() async {
    final r = _selected;
    if (r == null) return;
    final g = await _getGraph(_floor);
    if (g == null) return _toast('Для этого этажа ещё нет графа маршрутов');
    final path = g.routeFromNearestStairs(r.number);
    if (path == null) return _toast('Для кабинета ${r.number} маршрут пока недоступен');
    _applyRoute([...path, r.center]);
  }

  void _applyRoute(List<Offset> pts) {
    setState(() => _route = pts);
    var rect = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) { rect = rect.expandToInclude(Rect.fromPoints(p, p)); }
    _fitBounds(rect);
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<Suggestion> _suggest(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Suggestion>[];
    for (final e in _plans.entries) {
      for (final r in e.value.rooms) {
        if (r.number.toLowerCase().startsWith(q)) {
          out.add(Suggestion(r.number, 'Этаж ${e.key}', r.number));
        }
      }
    }
    final seen = <String>{};
    for (final l in _lessons) {
      final room = normRoom(l.room);
      if (room == null || l.teacher.isEmpty) continue;
      if (l.teacher.toLowerCase().contains(q) && seen.add('${l.teacher}|$room')) {
        out.add(Suggestion(l.teacher, 'ауд. $room', room, isTeacher: true));
      }
    }
    out.sort((a, b) => a.isTeacher == b.isTeacher ? a.label.compareTo(b.label) : (a.isTeacher ? 1 : -1));
    return out.take(6).toList();
  }

  List<Lesson> _upcoming(String room) {
    final today = DateTime.now().weekday - 1;
    final list = _lessons.where((l) => normRoom(l.room) == room).toList();
    list.sort((a, b) {
      final da = (a.dayIndex - today) % 7, db = (b.dayIndex - today) % 7;
      return da != db ? da.compareTo(db) : a.time.compareTo(b.time);
    });
    return list.take(5).toList();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // ───────────────────────── UI ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: MapStyle.canvas,
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Row(children: [
                  _roundButton(Icons.arrow_back, () {
                    if (widget.onBack != null) {
                      widget.onBack!();
                      return;
                    }
                    Navigator.maybePop(context);
                  }),
                  const SizedBox(width: 8),
                  Expanded(child: _buildBuildingPill()),
                ]),
                const SizedBox(height: 8),
                _buildSearch(),
              ],
            ),
          ),
          _buildFloorSwitcher(top + 124),
          if (_selected == null) _buildMapButtons(),
          if (_routeStart != null) _buildPickBanner(top + 124),
          if (_selected != null) _buildSheet(),
        ],
      ),
    );
  }

  Widget _buildBuildingPill() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final textColor = isDark ? Colors.white : MapStyle.ink;

    return Material(
      color: bgColor,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _pickBuilding,
        child: SizedBox(
          height: 48,
          child: Row(children: [
            const SizedBox(width: 14),
            const Icon(Icons.location_on, color: MapStyle.signal, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.buildingName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor))),
            Icon(Icons.keyboard_arrow_down, color: textColor),
            const SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }

  void _pickBuilding() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final b in kMapBuildings)
              ListTile(
                leading: Icon(Icons.location_on, color: b.id == widget.buildingId ? MapStyle.signal : MapStyle.mute),
                title: Text(b.name, style: TextStyle(fontWeight: b.id == widget.buildingId ? FontWeight.w800 : FontWeight.w600, color: MapStyle.ink)),
                subtitle: Text(b.address),
                onTap: () {
                  Navigator.pop(ctx);
                  if (b.id == widget.buildingId) return;
                  if (widget.onBuildingSelected != null) {
                    widget.onBuildingSelected!(b);
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => IndoorMapScreen(buildingId: b.id, buildingName: b.name, floors: b.floors)),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _zoom(double f) {
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    final m = Matrix4.identity()..translate(c.dx, c.dy)..scale(f)..translate(-c.dx, -c.dy);
    _transform.value = m * _transform.value;
  }

  Widget _buildMapButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final iconColor = isDark ? Colors.white : MapStyle.ink;

    Widget btn(IconData icon, VoidCallback onTap, {Color? color}) => Material(
      color: bgColor, elevation: 3, shape: const CircleBorder(),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 52, height: 52, child: Icon(icon, color: color ?? iconColor, size: 26))),
    );
    return Positioned(
      right: 12, bottom: 28,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.add, () => _zoom(1.5)),
        const SizedBox(height: 12),
        btn(Icons.remove, () => _zoom(1 / 1.5)),
        const SizedBox(height: 12),
        btn(Icons.navigation, _fitToScreen, color: MapStyle.signal),
      ]),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final iconColor = isDark ? Colors.white : MapStyle.ink;
    return Material(
      color: bgColor, elevation: 2, shape: const CircleBorder(),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 48, height: 48, child: Icon(icon, color: iconColor))),
    );
  }

  Widget _buildMap() {
    return LayoutBuilder(builder: (context, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      if (_loading) return const Center(child: CircularProgressIndicator());
      final plan = _plan;
      if (plan == null) return Center(child: Text(_error ?? 'Нет плана'));

      return InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        minScale: 0.1,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(2000),
        child: GestureDetector(
          onTapUp: (d) => _onTapRoom(plan.roomAt(d.localPosition)),
          child: SizedBox(
            width: plan.size.width,
            height: plan.size.height,
            child: Stack(children: [
              SvgPicture.string(plan.svg, width: plan.size.width, height: plan.size.height, fit: BoxFit.fill),
              CustomPaint(size: plan.size, painter: _HighlightPainter(_selected?.path)),
              if (_route != null) CustomPaint(size: plan.size, painter: _RoutePainter(_route!)),
              AnimatedBuilder(
                animation: _transform,
                builder: (_, __) {
                  final scale = _transform.value.getMaxScaleOnAxis();
                  if (scale < _fitScale * 1.6) return const SizedBox.shrink();
                  return CustomPaint(size: plan.size, painter: _LabelPainter(plan.labels, scale));
                },
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _buildSearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final textColor = isDark ? Colors.white : MapStyle.ink;
    final hintColor = isDark ? Colors.white70 : MapStyle.mute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<Suggestion>(
          optionsBuilder: (v) => _suggest(v.text),
          displayStringForOption: (s) => s.label,
          onSelected: (s) => _findRoom(s.room),
          fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => Material(
            color: searchBg,
            elevation: 2,
            borderRadius: BorderRadius.circular(24),
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 16, color: textColor),
              onSubmitted: (v) {
                final s = _suggest(v);
                _findRoom(s.isNotEmpty ? s.first.room : v);
              },
              decoration: InputDecoration(
                hintText: 'Кабинет или преподаватель',
                hintStyle: TextStyle(color: hintColor),
                prefixIcon: Icon(Icons.search, color: hintColor),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          optionsViewBuilder: (ctx, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              color: searchBg,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _viewport.width - 80, maxHeight: 300),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final s in options)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          s.isTeacher ? Icons.person_outline : Icons.meeting_room_outlined,
                          color: hintColor,
                        ),
                        title: Text(
                          s.label,
                          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                        ),
                        subtitle: Text(
                          s.subtitle,
                          style: TextStyle(color: hintColor),
                        ),
                        onTap: () => onSelected(s),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloorSwitcher(double top) {
    if (widget.floors.length < 2) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final textColor = isDark ? Colors.white : MapStyle.ink;

    final order = [_floor, ...widget.floors.where((f) => f != _floor)];
    return Positioned(
      right: 12, top: top,
      child: Material(
        color: bgColor, elevation: 3, borderRadius: BorderRadius.circular(18), clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in order)
              InkWell(
                onTap: () => _setFloor(f),
                child: Container(
                  width: 54, height: 54, alignment: Alignment.center,
                  color: f == _floor ? MapStyle.signal : Colors.transparent,
                  child: Text('$f', style: TextStyle(fontSize: f == _floor ? 26 : 20, fontWeight: FontWeight.w700, color: f == _floor ? Colors.white : textColor, fontFeatures: MapStyle.tabular)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickBanner(double top) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : MapStyle.ink;
    final textColor = isDark ? Colors.white : Colors.white; // В темной тоже белый

    return Positioned(
      top: top, left: 12, right: 72,
      child: Material(
        color: bgColor, borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(children: [
            Expanded(child: Text('Старт: $_routeStart. Выбери кабинет, куда идти', style: TextStyle(color: textColor, fontSize: 14))),
            IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => setState(() => _routeStart = null)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final titleColor = isDark ? Colors.white : MapStyle.ink;
    final subtitleColor = isDark ? Colors.white70 : MapStyle.slate;
    final hintColor = isDark ? Colors.white54 : MapStyle.mute;

    final r = _selected!;
    final lessons = _upcoming(r.number);
    final teachers = { for (final l in _lessons.where((l) => normRoom(l.room) == r.number)) if (l.teacher.isNotEmpty) l.teacher }.toList();
    final title = _info?.title ?? 'Аудитория ${r.number}';
    final hasOwnTitle = title != 'Аудитория ${r.number}';

    return DraggableScrollableSheet(
      key: ValueKey(r.number),
      initialChildSize: 0.3, minChildSize: 0.14, maxChildSize: 0.7,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(blurRadius: 16, color: Color(0x26000000))],
        ),
        child: ListView(
          controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 12, 28),
          children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12, right: 8), decoration: BoxDecoration(color: isDark ? Colors.white24 : const Color(0x1F000000), borderRadius: BorderRadius.circular(2)))),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(r.number, style: TextStyle(fontSize: 46, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1, color: titleColor, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasOwnTitle) Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: subtitleColor)),
                        Text('$_floor этаж', style: TextStyle(fontSize: 14, color: hintColor)),
                      ],
                    ),
                  ),
                ),
                IconButton(icon: Icon(Icons.close, color: hintColor), onPressed: () => setState(() { _selected = null; _route = null; _routeStart = null; })),
              ],
            ),
            if ((_info?.department ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_info!.department, style: TextStyle(fontSize: 15, color: subtitleColor)),
            ],
            if ((_info?.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_info!.description, style: TextStyle(fontSize: 15, color: subtitleColor)),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: titleColor, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _routeFromStairs, child: Text('Как дойти', style: TextStyle(color: isDark ? Colors.black : Colors.white)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: titleColor, minimumSize: const Size.fromHeight(48), side: const BorderSide(color: MapStyle.lake, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => setState(() { _routeStart = r.number; _route = null; }), child: const Text('Маршрут отсюда'))),
              ]),
            ),
            if (teachers.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('Преподаватели', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor)),
              const SizedBox(height: 6),
              for (final t in teachers) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(t, style: TextStyle(fontSize: 15, color: subtitleColor))),
            ],
            const SizedBox(height: 22),
            Text('Ближайшие пары', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor)),
            const SizedBox(height: 6),
            if (lessons.isEmpty) Text('В расписании нет занятий в этом кабинете', style: TextStyle(fontSize: 14, color: hintColor))
            else
              for (final l in lessons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 92, child: Text(l.time, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor, fontFeatures: const [FontFeature.tabularFigures()]))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.subject, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: subtitleColor)),
                            Text('${_dayNames[l.dayIndex.clamp(0, 5)]}, ${l.group}', style: TextStyle(fontSize: 13, color: hintColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Painters ─────────────────────────
class _HighlightPainter extends CustomPainter {
  final Path? path;
  _HighlightPainter(this.path);

  @override
  void paint(Canvas canvas, Size size) {
    if (path == null) return;
    canvas.drawPath(path!, Paint()..color = MapStyle.selected);
    canvas.drawPath(path!, Paint()..color = MapStyle.signal..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => old.path != path;
}

class _RoutePainter extends CustomPainter {
  final List<Offset> pts;
  _RoutePainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
    Paint line(Color c, double w) => Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line(Colors.white, 13));
    canvas.drawPath(path, line(MapStyle.signal, 7));

    canvas.drawCircle(pts.first, 20, Paint()..color = MapStyle.signal.withValues(alpha: 0.18));
    canvas.drawCircle(pts.first, 10, Paint()..color = Colors.white);
    canvas.drawCircle(pts.first, 7, Paint()..color = MapStyle.signal);

    final tip = pts.last;
    final head = tip + const Offset(0, -36);
    final pin = Path()..moveTo(tip.dx, tip.dy)..lineTo(head.dx - 11, head.dy + 7)..lineTo(head.dx + 11, head.dy + 7)..close();
    canvas.drawPath(pin, Paint()..color = MapStyle.pin);
    canvas.drawCircle(head, 15, Paint()..color = Colors.white);
    canvas.drawCircle(head, 13, Paint()..color = MapStyle.pin);
    canvas.drawCircle(head, 5, Paint()..color = const Color(0xFF7A1F2B));
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.pts != pts;
}

class _LabelPainter extends CustomPainter {
  final List<MapLabel> labels;
  final double scale;
  _LabelPainter(this.labels, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final fs = (13 / scale).clamp(6.0, 20.0);
    for (final l in labels) {
      final tp = TextPainter(text: TextSpan(text: l.text, style: TextStyle(fontSize: fs, color: MapStyle.ink, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
      canvas.save();
      canvas.translate(l.pos.dx, l.pos.dy);
      canvas.rotate(l.rotation);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LabelPainter old) => old.scale != scale || old.labels != labels;
}