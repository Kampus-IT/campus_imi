// lib/utils/group_code_helper.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupCodeHelper {
  /// Генерация случайного секретного кода (6 символов, без путающих букв O, 0, I, 1)
  static String generateRandomCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Разовая миграция: проходит по всем группам и проставляет код, если его нет
  static Future<int> migrateExistingGroupsCodes({
    void Function(int done, int total)? onProgress,
  }) async {
    final db = FirebaseFirestore.instance;
    final snapshot = await db.collection('groups').get();

    if (snapshot.docs.isEmpty) return 0;

    int updatedCount = 0;
    final total = snapshot.docs.length;

    for (int i = 0; i < total; i++) {
      final doc = snapshot.docs[i];
      final data = doc.data();

      // Если кода нет или он пустой — генерируем новый
      if (data['code'] == null || (data['code'] as String).isEmpty) {
        String newCode;
        bool exists;

        // Защита от случайной коллизии кодов
        do {
          newCode = generateRandomCode();
          final check = await db
              .collection('groups')
              .where('code', isEqualTo: newCode)
              .get();
          exists = check.docs.isNotEmpty;
        } while (exists);

        // Обновляем документ группы, добавляя секретный код
        await doc.reference.set({
          'code': newCode,
        }, SetOptions(merge: true));

        updatedCount++;
      }

      onProgress?.call(i + 1, total);
    }

    return updatedCount;
  }
}