import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'excel_schedule_parser.dart';

class ScheduleImportService {
  final _db = FirebaseFirestore.instance;

  String _docId(ParsedLesson l) {
    // Преподаватель, кабинет и тип входят в ключ: две подгруппы в одно время не затирают друг друга.
    final key = '${l.group}|${l.dayIndex}|${l.week}|${l.time}|${l.subject}|${l.teacher}|${l.room}|${l.type}';
    return md5.convert(utf8.encode(key)).toString();
  }

  /// Импорт: удаляет старые пары затронутых групп и пишет новые.
  Future<int> importLessons(
      List<ParsedLesson> lessons, {
        void Function(int done, int total)? onProgress,
      }) async {
    if (lessons.isEmpty) return 0;

    final groups = lessons.map((l) => l.group).toSet();
    final newIds = lessons.map(_docId).toSet();

    // 1. Сначала пишем новые пары (чанками по 400). Если импорт прервётся,
    //    старое расписание останется на месте, а не пропадёт целиком.
    var done = 0;
    for (var i = 0; i < lessons.length; i += 400) {
      final chunk = lessons.sublist(i, (i + 400).clamp(0, lessons.length));
      final batch = _db.batch();
      for (final l in chunk) {
        batch.set(
          _db.collection('lessons').doc(_docId(l)),
          {
            ...l.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        done++;
        onProgress?.call(done, lessons.length);
      }
      await batch.commit();
    }

    // 2. Затем удаляем устаревшие пары этих групп (те, которых нет в новом файле).
    for (final g in groups) {
      final old = await _db
          .collection('lessons')
          .where('group', isEqualTo: g)
          .get();
      final stale = old.docs.where((d) => !newIds.contains(d.id)).toList();
      for (var i = 0; i < stale.length; i += 400) {
        final batch = _db.batch();
        for (final doc in stale.skip(i).take(400)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    return lessons.length;
  }
}