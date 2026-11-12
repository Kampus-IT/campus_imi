import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/lesson.dart';

class SvfuGroup {
  final String name;        // Полное имя из API, например "С-ЛД-24-1/2F1"
  final int id;             // ID группы в API
  final String cleanName;   // Без префикса факультета, со слешем: "ЛД-24-1/2F1"
  final String safeId;      // Безопасный ID для Firestore: "ЛД-24-1_2F1"
  final int course;

  SvfuGroup({
    required this.name,
    required this.id,
    required this.cleanName,
    required this.safeId,
    required this.course,
  });
}

class SvfuScheduleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _baseUrl = 'https://eios.s-vfu.ru/api';

  // ⚠️ Обновите токен, если получите 401/403
  static const String _authToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9uYW1lIjoia2VzaGFfMDA3QGljbG91ZC5jb20iLCJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9zdXJuYW1lIjoi0JrQuNGA0LXQvdGB0LrQuNC5INCYLiDQmC4iLCJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9oYXNoIjoiIiwiaHR0cDovL3NjaGVtYXMueG1sc29hcC5vcmcvd3MvMjAwNS8wNS9pZGVudGl0eS9jbGFpbXMvc2lkIjoiLTEyMjM4OCIsImh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd3MvMjAwOC8wNi9pZGVudGl0eS9jbGFpbXMvdXNlcmRhdGEiOiIyIiwidmVyaWZTdHJpbmciOiIiLCJuYmYiOjE3OTM1NDQyMDEsImV4cCI6MTc5NDE5OTQwMSwiaXNzIjoiV2ViQXBwIiwiYXVkIjoiTU1JU0xhYiJ9.yTT_45nYgBw_-ncf8BTm9Y44J05HjOES5aoMleXvcn0';

  Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Accept-Language': 'ru,en;q=0.9',
    'Referer': 'https://eios.s-vfu.ru/WebApp/',
    'Origin': 'https://eios.s-vfu.ru',
    'Authorization': 'Bearer $_authToken',
    'client-version': '2026-10-24T10:59:44.100Z',
  };

  // --- Утилиты для работы со слешами ---

  /// Убирает префикс факультета: "С-ЛД-24-1/2F1" -> "ЛД-24-1/2F1"
  String _cleanGroupName(String rawGroup) {
    return rawGroup.replaceFirst(RegExp(r'^[А-ЯЁA-Z]{2,5}-'), '').trim();
  }

  /// Делает безопасный ID для Firestore: "ЛД-24-1/2F1" -> "ЛД-24-1_2F1"
  String _safeIdFromName(String cleanName) {
    return cleanName.replaceAll('/', '_').replaceAll('\\', '_').trim();
  }

  // --- API-методы ---

  Future<List<SvfuGroup>> getAllGroups() async {
    try {
      final url = Uri.parse('$_baseUrl/raspGrouplist?year=2026-2027');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ [SVFU] Ошибка загрузки групп: Статус ${response.statusCode}');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      final dynamic json = jsonDecode(utf8.decode(response.bodyBytes));
      final List<dynamic> groupsList = json is List ? json : (json['data'] as List? ?? []);

      return groupsList.map((g) {
        final rawName = (g['name'] ?? '').toString();
        final clean = _cleanGroupName(rawName);
        return SvfuGroup(
          name: rawName,
          id: g['id'] as int? ?? 0,
          cleanName: clean,
          safeId: _safeIdFromName(clean),
          course: g['kurs'] as int? ?? 1,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ [SVFU] Ошибка загрузки групп: $e');
      throw Exception('Не удалось загрузить список групп: $e');
    }
  }

  Future<List<String>> getSemesterDates(int groupId) async {
    try {
      final url = Uri.parse('$_baseUrl/GetRaspDates?idGroup=$groupId');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 30));

      debugPrint('🔍 [SVFU] GetRaspDates Status: ${response.statusCode}');
      debugPrint('🔍 [SVFU] GetRaspDates Body: ${response.body}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('❌ [SVFU] Токен истек (401/403)! Обновите _authToken.');
        throw Exception('Токен авторизации устарел');
      }
      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      final dynamic json = jsonDecode(utf8.decode(response.bodyBytes));
      List<dynamic>? datesList;

      if (json is Map<String, dynamic>) {
        if (json['data'] is Map<String, dynamic> && json['data']['dates'] is List) {
          datesList = json['data']['dates'] as List?;
        } else if (json['data'] is List) {
          datesList = json['data'] as List?;
        } else if (json['dates'] is List) {
          datesList = json['dates'] as List?;
        }
      } else if (json is List) {
        datesList = json;
      }

      if (datesList == null || datesList.isEmpty) {
        debugPrint('⚠️ [SVFU] Список дат пуст для groupId=$groupId');
        return [];
      }

      return datesList.map((d) => d.toString()).toList();
    } catch (e) {
      debugPrint('❌ [SVFU] Ошибка getSemesterDates($groupId): $e');
      throw Exception('Не удалось загрузить учебные даты: $e');
    }
  }

  Future<int> importGroupSchedule({
    required int groupId,
    required String groupName,
    required String departmentId,
    void Function(int done, int total)? onProgress,
  }) async {
    try {
      final cleanName = _cleanGroupName(groupName);
      final safeId = _safeIdFromName(cleanName); // ← для doc.id и префикса ID пар

      final dates = await getSemesterDates(groupId);
      if (dates.isEmpty) {
        debugPrint('⚠️ [SVFU] Нет дат для группы $cleanName — пропускаем.');
        return 0;
      }

      debugPrint('▶️ [SVFU] Импорт группы $cleanName (safeId=$safeId, дат: ${dates.length})');

      final List<Lesson> parsedLessons = [];
      final seenIds = <String>{};

      // Стабильный числовой префикс для ID пар (без слешей)
      final groupHash = safeId.hashCode;

      for (int i = 0; i < dates.length; i++) {
        final dateStr = dates[i];
        final url = Uri.parse('$_baseUrl/Rasp?idGroup=$groupId&sdate=$dateStr');

        try {
          final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) continue;

          final json = jsonDecode(utf8.decode(response.bodyBytes));
          final List<dynamic> rasp = json['data']?['rasp'] ?? [];

          for (var item in rasp) {
            try {
              final String rawDiscipline = item['дисциплина'] ?? '';
              String type = 'пр';
              String subject = rawDiscipline;
              int? subgroup;

              final subMatch = RegExp(
                r'(?:([12])\s*(?:пг|п/г|пр|пн))|(?:(?:пг|п/г|пр|пн)\s*([12]))',
                caseSensitive: false,
              ).firstMatch(rawDiscipline);

              if (subMatch != null) {
                final digitStr = subMatch.group(1) ?? subMatch.group(2);
                subgroup = int.tryParse(digitStr ?? '');
                subject = subject.replaceAll(subMatch.group(0)!, '').trim();
              }

              int weekType = item['типНедели'] ?? 0;
              if (weekType == 0) {
                if (rawDiscipline.startsWith('**')) weekType = 2;
                else if (rawDiscipline.startsWith('*')) weekType = 1;
              }

              subject = subject.replaceAll(RegExp(r'^\*+\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
              if (subject.startsWith('Лек ')) { type = 'лек'; subject = subject.substring(4).trim(); }
              else if (subject.startsWith('Лаб ')) { type = 'лаб'; subject = subject.substring(4).trim(); }
              else if (subject.startsWith('Пр. ')) { type = 'пр'; subject = subject.substring(4).trim(); }
              subject = subject.replaceAll(RegExp(r'[,\.]\s*$'), '').trim();

              final int dayIndex = (item['деньНедели'] as int) - 1;
              if (dayIndex < 0 || dayIndex > 5) continue;

              int week = 0;
              if (weekType == 1) week = 1;
              if (weekType == 2) week = 2;

              // ✅ ID пары — без слешей (используем safeId-hash вместо cleanName)
              final String docId =
                  '${groupHash}_${dayIndex}_${item['начало']}_${subject.hashCode}_${week}_${subgroup ?? 0}';
              if (seenIds.contains(docId)) continue;
              seenIds.add(docId);

              final lesson = Lesson(
                id: docId,
                time: '${item['начало']}-${item['конец']}',
                subject: subject,
                room: item['аудитория'] ?? '',
                teacher: item['преподаватель'] ?? '',
                type: type,
                dayIndex: dayIndex,
                group: cleanName, // ← со слешем, это значение поля — допустимо
                week: week,
                subgroup: subgroup,
              );

              parsedLessons.add(lesson);
            } catch (e) {
              debugPrint('❌ [SVFU] Ошибка парсинга пары: $e');
            }
          }
        } catch (e) {
          debugPrint('⚠️ [SVFU] Ошибка загрузки даты $dateStr: $e');
        }

        if (onProgress != null) onProgress(i + 1, dates.length);
      }

      if (parsedLessons.isEmpty) {
        debugPrint('⚠️ [SVFU] 0 пар для $cleanName — база не тронута.');
        return 0;
      }

      // Удаляем старые пары — фильтр по ПОЛЮ 'group' (значение, слеш ок)
      debugPrint('🗑️ [SVFU] Удаляем старые пары $cleanName...');
      final oldLessons = await _db
          .collection('lessons')
          .where('group', isEqualTo: cleanName)
          .get();
      for (var i = 0; i < oldLessons.docs.length; i += 400) {
        final batch = _db.batch();
        for (var doc in oldLessons.docs.skip(i).take(400)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // ✅ Сохраняем документ группы по безопасному ID
      final groupRef = _db.collection('groups').doc(safeId);
      await groupRef.set({
        'name': cleanName,       // отображаемое имя (со слешем)
        'safeId': safeId,        // безопасный ID
        'departmentId': departmentId,
      }, SetOptions(merge: true));

      // Сохраняем пары (ID уже безопасные)
      debugPrint('💾 [SVFU] Сохраняем ${parsedLessons.length} пар для $cleanName...');
      for (var i = 0; i < parsedLessons.length; i += 400) {
        final batch = _db.batch();
        for (var lesson in parsedLessons.skip(i).take(400)) {
          batch.set(_db.collection('lessons').doc(lesson.id), lesson.toMap());
        }
        await batch.commit();
      }

      debugPrint('✅ [SVFU] Группа $cleanName импортирована (${parsedLessons.length} пар).');
      return parsedLessons.length;
    } catch (e) {
      throw Exception('Не удалось импортировать расписание: $e');
    }
  }

  Future<int> importFacultySchedule({
    required String facultyCode,
    required String departmentId,
    void Function(int done, int total, String currentGroup)? onProgress,
  }) async {
    try {
      final allGroups = await getAllGroups();
      final facultyGroups =
      allGroups.where((g) => g.name.startsWith('$facultyCode-')).toList();

      if (facultyGroups.isEmpty) {
        throw Exception('Не найдено групп для факультета $facultyCode');
      }

      debugPrint('▶️ [SVFU] Импорт факультета $facultyCode (групп: ${facultyGroups.length})');

      int totalLessons = 0;
      for (int i = 0; i < facultyGroups.length; i++) {
        final group = facultyGroups[i];
        if (onProgress != null) onProgress(i + 1, facultyGroups.length, group.cleanName);

        try {
          final count = await importGroupSchedule(
            groupId: group.id,
            groupName: group.name,
            departmentId: departmentId,
          );
          totalLessons += count;
        } catch (e) {
          debugPrint('⚠️ [SVFU] Пропущена группа ${group.cleanName}: $e');
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('✅ [SVFU] Импорт $facultyCode завершён. Всего пар: $totalLessons');
      return totalLessons;
    } catch (e) {
      throw Exception('Не удалось импортировать факультет: $e');
    }
  }
}