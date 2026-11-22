// lib/utils/room_index.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../screens/indoor_map_screen.dart' show normRoom;
import '../screens/map_data.dart';

class RoomIndex {
  final Map<String, List<String>> byNumber; // "325" → ["guk2", "guk3"]
  RoomIndex(this.byNumber);

  static RoomIndex? _cache;

  static Future<RoomIndex> load() async {
    if (_cache != null) return _cache!;
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/maps/room_index.json'))
      as Map<String, dynamic>;
      return _cache = RoomIndex({
        for (final e in j.entries) e.key: [for (final x in e.value as List) x.toString()]
      });
    } catch (_) {
      return _cache = RoomIndex({});
    }
  }

  /// Группа корпуса по подсказке в тексте («кит-205» → kit).
  String? groupFromText(String text) {
    final t = text.toLowerCase();
    for (final e in kGroupAliases.entries) {
      for (final a in e.value) {
        if (t.contains(a)) return e.key;
      }
    }
    return null;
  }

  /// Блоки карты, где есть кабинет [number] (и нужный корпус, если он известен).
  List<MapBuilding> blocksFor(String number, {String? building, String text = ''}) {
    final group = (building != null && building.isNotEmpty) ? building : groupFromText(text);
    final out = <MapBuilding>[];
    for (final id in byNumber[number.toLowerCase()] ?? const <String>[]) {
      final b = mapBuildingById(id);
      if (b != null && (group == null || b.group == group)) out.add(b);
    }
    return out;
  }

  /// Показывать ли занятие на карте блока [b].
  bool shows({required String room, required String building, required MapBuilding b}) {
    final n = normRoom(room);
    if (n == null) return false;
    final blocks = blocksFor(n, building: building, text: room);
    if (blocks.isEmpty) return false;
    // неоднозначно (номер есть в нескольких корпусах, а корпус занятия не указан)
    final groups = blocks.map((x) => x.group).toSet();
    if (groups.length > 1) return false;
    return blocks.any((x) => x.id == b.id);
  }
}