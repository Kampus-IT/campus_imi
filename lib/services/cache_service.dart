// lib/services/cache_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ Добавлен для Timestamp
import '../models/lesson.dart';
import '../models/news_model.dart';
import '../models/institute_info.dart';

/// Централизованный кэш на SharedPreferences.
class CacheService {
  CacheService._();

  // ---------- КЛЮЧИ ----------
  static const String _mapLessonsKey = 'cached_map_v2';
  static const String _mapTimeKey = 'cache_time_map_v2';

  static const String _newsKey = 'cached_news_v3';
  static const String _newsTimeKey = 'cache_time_news_v3';

  static const String _institutesKey = 'cached_institutes_v3';
  static const String _institutesTimeKey = 'cache_time_institutes_v3';

  static const String _groupsKey = 'cached_groups_v3';

  static String _lessonsKey(String group) =>
      'cached_lessons_v3_${_sanitize(group)}';

  static String _lessonsTimeKey(String group) =>
      'cache_time_lessons_v3_${_sanitize(group)}';

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  // ---------- РАСПИСАНИЕ ----------
  static Future<void> saveLessons(String group, List<Lesson> lessons) async {
    final prefs = await SharedPreferences.getInstance();
    final data = lessons.map((l) => l.toMap()).toList();
    await prefs.setString(_lessonsKey(group), jsonEncode(data));
    await prefs.setInt(
        _lessonsTimeKey(group), DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Lesson>> loadLessons(String group) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_lessonsKey(group));
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list
          .map((m) =>
          Lesson.fromMap('', Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isLessonsFresh(String group,
      {Duration maxAge = const Duration(hours: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lessonsTimeKey(group));
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateLessons(String group) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lessonsTimeKey(group));
  }

  // ---------- КАРТА ----------
  static Future<void> saveMapLessons(List<Lesson> lessons) async {
    final prefs = await SharedPreferences.getInstance();
    final data = lessons.map((l) => l.toMap()).toList();
    await prefs.setString(_mapLessonsKey, jsonEncode(data));
    await prefs.setInt(_mapTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Lesson>> loadMapLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_mapLessonsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list
          .map((m) =>
          Lesson.fromMap('', Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isMapFresh(
      {Duration maxAge = const Duration(hours: 6)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_mapTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  // ---------- ГРУППЫ ----------
  static Future<void> saveGroups(Map<String, String> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups));
  }

  static Future<Map<String, String>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_groupsKey);
    if (str == null) return {};
    try {
      final map = jsonDecode(str) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  // ---------- НОВОСТИ ----------
  static Future<void> saveNews(List<News> newsList) async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ Исправление: безопасно сериализуем Timestamp
    final data = newsList.map((n) {
      final map = n.toMap();
      if (map['createdAt'] is Timestamp) {
        map['createdAt'] =
            (map['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return <String, dynamic>{...map, 'id': n.id};
    }).toList();
    await prefs.setString(_newsKey, jsonEncode(data));
  }

  static Future<List<News>> loadNews() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_newsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        final id = (map['id'] ?? '').toString();
        return News.fromMap(map, id);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Сливает новые новости со старыми из кэша.
  static Future<List<News>> loadNewsMerged(List<News> fresh) async {
    final cached = await loadNews();
    if (cached.isEmpty) {
      await saveNews(fresh);
      return fresh;
    }
    final Map<String, News> map = {for (final n in cached) n.id: n};
    for (final n in fresh) {
      map[n.id] = n;
    }
    final merged = map.values.toList()
      ..sort((a, b) {
        final da = a.createdAt ?? DateTime.now();
        final db = b.createdAt ?? DateTime.now();
        return db.compareTo(da);
      });
    await saveNews(merged);
    return merged;
  }

  static Future<void> saveNewsTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_newsTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> isNewsFresh(
      {Duration maxAge = const Duration(minutes: 15)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_newsTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateNews() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_newsTimeKey);
  }

  // ---------- ИНСТИТУТЫ ----------
  static Future<void> saveInstitutes(List<InstituteInfo> institutes) async {
    final prefs = await SharedPreferences.getInstance();
    final data = institutes
        .map((i) => <String, dynamic>{
      'id': i.id,
      'name': i.name,
      'shortName': i.shortName,
      'type': i.type,
      'order': i.order,
      'isActive': i.isActive,
      'logoUrl': i.logoUrl,
      'about': i.about,
      'history': i.history,
      'directions': i.directions,
    })
        .toList();
    await prefs.setString(_institutesKey, jsonEncode(data));
  }

  static Future<List<InstituteInfo>> loadInstitutes() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_institutesKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        final id = (map['id'] ?? '').toString();
        return InstituteInfo.fromMap(id, map);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveInstitutesTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _institutesTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> isInstitutesFresh(
      {Duration maxAge = const Duration(hours: 24)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_institutesTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateInstitutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_institutesTimeKey);
  }

  // ---------- ОЧИСТКА ----------
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) =>
    k.startsWith('cached_') || k.startsWith('cache_time_'));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ---------- АДМИНСКИЕ ДАННЫЕ ----------
  static const String _adminUsersKey = 'cached_admin_users_v1';
  static const String _adminUsersTimeKey = 'cache_time_admin_users_v1';
  static const String _adminEventsKey = 'cached_admin_events_v1';
  static const String _adminEventsTimeKey = 'cache_time_admin_events_v1';
  static const String _adminGroupsKey = 'cached_admin_groups_v1';
  static const String _adminGroupsTimeKey = 'cache_time_admin_groups_v1';
  static const String _adminLessonsKey = 'cached_admin_lessons_v1';
  static const String _adminLessonsTimeKey = 'cache_time_admin_lessons_v1';
  static const String _adminDepartmentsKey = 'cached_admin_departments_v1';
  static const String _adminDepartmentsTimeKey =
      'cache_time_admin_departments_v1';

  // --- USERS ---
  static Future<void> saveAdminUsers(List<Map<String, dynamic>> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminUsersKey, jsonEncode(users));
    await prefs.setInt(
        _adminUsersTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> loadAdminUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_adminUsersKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAdminUsersFresh(
      {Duration maxAge = const Duration(minutes: 10)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_adminUsersTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateAdminUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminUsersTimeKey);
  }

  // --- EVENTS ---
  static Future<void> saveAdminEvents(List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminEventsKey, jsonEncode(events));
    await prefs.setInt(
        _adminEventsTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> loadAdminEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_adminEventsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAdminEventsFresh(
      {Duration maxAge = const Duration(minutes: 5)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_adminEventsTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateAdminEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminEventsTimeKey);
  }

  // --- GROUPS ---
  static Future<void> saveAdminGroups(List<Map<String, dynamic>> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminGroupsKey, jsonEncode(groups));
    await prefs.setInt(
        _adminGroupsTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> loadAdminGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_adminGroupsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAdminGroupsFresh(
      {Duration maxAge = const Duration(hours: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_adminGroupsTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateAdminGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminGroupsTimeKey);
  }

  // --- LESSONS ---
  static Future<void> saveAdminLessons(
      List<Map<String, dynamic>> lessons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminLessonsKey, jsonEncode(lessons));
    await prefs.setInt(
        _adminLessonsTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> loadAdminLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_adminLessonsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAdminLessonsFresh(
      {Duration maxAge = const Duration(hours: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_adminLessonsTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateAdminLessons() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminLessonsTimeKey);
  }

  // --- DEPARTMENTS ---
  static Future<void> saveAdminDepartments(
      List<Map<String, dynamic>> depts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminDepartmentsKey, jsonEncode(depts));
    await prefs.setInt(
        _adminDepartmentsTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> loadAdminDepartments() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_adminDepartmentsKey);
    if (str == null) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAdminDepartmentsFresh(
      {Duration maxAge = const Duration(hours: 2)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_adminDepartmentsTimeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        maxAge;
  }

  static Future<void> invalidateAdminDepartments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminDepartmentsTimeKey);
  }
}