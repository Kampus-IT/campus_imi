import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/lesson.dart';
import 'notification_service.dart';

class LessonOccurrence {
  final Lesson lesson;
  final DateTime start;
  final DateTime end;
  const LessonOccurrence(this.lesson, this.start, this.end);

  bool isActiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  double progressAt(DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    final passed = now.difference(start).inSeconds;
    return (passed / total).clamp(0.0, 1.0).toDouble();
  }
}

class ScheduleService {
  ScheduleService._();
  static List<DateTime>? _cachedOddWeeks;

  static final List<DateTime> _defaultOddWeeks = [
    DateTime(2026, 8, 31), DateTime(2026, 9, 14), DateTime(2026, 9, 28),
    DateTime(2026, 10, 12), DateTime(2026, 10, 26), DateTime(2026, 11, 9),
    DateTime(2026, 11, 23), DateTime(2026, 12, 7), DateTime(2026, 12, 21),
  ];

  static Future<List<DateTime>> loadOddWeeks() async {
    final cached = _cachedOddWeeks;
    if (cached != null) return cached;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('semester_calendar')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final raw = snapshot.docs.first.data()['odd_weeks'];
        final result = <DateTime>[];
        if (raw is List) {
          for (final item in raw) {
            final parts = item.toString().split('-');
            if (parts.length != 3) continue;
            final y = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            final d = int.tryParse(parts[2]);
            if (y == null || m == null || d == null) continue;
            result.add(DateTime(y, m, d));
          }
        }
        if (result.isNotEmpty) {
          _cachedOddWeeks = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки календаря: $e');
    }
    return _defaultOddWeeks;
  }

  static void resetCache() => _cachedOddWeeks = null;
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime mondayOf(DateTime d) {
    final x = dateOnly(d);
    return DateTime(x.year, x.month, x.day - (x.weekday - 1));
  }

  static int weekNumber(DateTime date, List<DateTime> oddWeeks) {
    final target = dateOnly(date);
    for (final start in oddWeeks) {
      final s = dateOnly(start);
      final endExclusive = DateTime(s.year, s.month, s.day + 7);
      if (!target.isBefore(s) && target.isBefore(endExclusive)) return 1;
    }
    return 2;
  }

  static List<int> _timeMatches(String raw) {
    final matches = RegExp(r'(\d{1,2})[:.](\d{2})').allMatches(raw).toList();
    final result = <int>[];
    for (final m in matches.take(2)) {
      final h = int.tryParse(m.group(1) ?? '');
      final min = int.tryParse(m.group(2) ?? '');
      if (h == null || min == null || h > 23 || min > 59) return const [];
      result.add(h * 60 + min);
    }
    return result;
  }

  static int startMinutes(Lesson l) {
    final t = _timeMatches(l.time);
    return t.isEmpty ? 24 * 60 : t.first;
  }

  static LessonOccurrence? occurrenceFor(Lesson lesson, DateTime date) {
    final t = _timeMatches(lesson.time);
    if (t.isEmpty) return null;
    final day = dateOnly(date);
    final start = DateTime(day.year, day.month, day.day, 0, t.first);
    final endMinutes = t.length > 1 ? t[1] : t.first + 95;
    final end = DateTime(day.year, day.month, day.day, 0, endMinutes);
    return LessonOccurrence(lesson, start, end);
  }

  static List<Lesson> lessonsForDate(
      List<Lesson> all,
      DateTime date,
      List<DateTime> oddWeeks, {
        int? userSubgroup, // <-- Добавлено
      }) {
    final dayIndex = date.weekday - 1;
    final week = weekNumber(date, oddWeeks);

    final result = all.where((l) {
      if (l.dayIndex != dayIndex) return false;
      if (l.week != 0 && l.week != week) return false;

      if (userSubgroup != null && l.subgroup != null) {
        if (l.subgroup != userSubgroup) return false;
      }
      return true;
    }).toList();

    result.sort((a, b) => startMinutes(a).compareTo(startMinutes(b)));
    return result;
  }

  // ✅ ИСПРАВЛЕНО: добавлен userSubgroup
  static List<LessonOccurrence> occurrences(
      List<Lesson> all,
      DateTime from,
      List<DateTime> oddWeeks, {
        int days = 14,
        int? userSubgroup, // <-- Добавлено
      }) {
    final start = dateOnly(from);
    final result = <LessonOccurrence>[];
    for (int i = 0; i < days; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      // Передаем подгруппу в lessonsForDate
      for (final lesson in lessonsForDate(all, date, oddWeeks, userSubgroup: userSubgroup)) {
        final occ = occurrenceFor(lesson, date);
        if (occ != null) result.add(occ);
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static LessonOccurrence? current(List<LessonOccurrence> list, DateTime now) {
    for (final o in list) {
      if (o.isActiveAt(now)) return o;
    }
    return null;
  }

  static LessonOccurrence? next(List<LessonOccurrence> list, DateTime now) {
    for (final o in list) {
      if (o.start.isAfter(now)) return o;
    }
    return null;
  }

  // ✅ ИСПРАВЛЕНО: добавлен userSubgroup
  static Future<void> rescheduleReminders(
      List<Lesson> all,
      List<DateTime> oddWeeks, {
        int? userSubgroup, // <-- Добавлено
      }) async {
    final now = DateTime.now();
    final list = occurrences(all, now, oddWeeks, days: 14, userSubgroup: userSubgroup);
    final reminders = <LessonReminder>[
      for (final o in list)
        if (o.start.isAfter(now))
          LessonReminder(
            key: '${o.lesson.id}_${o.start.toIso8601String()}',
            subject: o.lesson.subject,
            room: o.lesson.room,
            time: o.lesson.time,
            start: o.start,
          ),
    ];
    await NotificationService.scheduleLessonReminderList(reminders);
  }
}