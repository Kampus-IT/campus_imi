import 'package:cloud_firestore/cloud_firestore.dart';
import 'building_resolver.dart';

class MigrationReport {
  int total = 0;
  int updated = 0;
  int skipped = 0;
  List<String> errors = [];
}

Future<MigrationReport> migrateLessonsBuildings() async {
  final db = FirebaseFirestore.instance;
  final report = MigrationReport();

  try {
    final snap = await db.collection('lessons').get();
    report.total = snap.docs.length;

    var batch = db.batch();
    var inBatch = 0;

    for (final doc in snap.docs) {
      try {
        final data = doc.data();
        final rawRoom = (data['room'] ?? '').toString().trim();
        final currentBuilding = (data['building'] ?? '').toString().trim();

        // Если у пары уже есть корпус и номер чистый — пропускаем
        if (currentBuilding.isNotEmpty && !rawRoom.toUpperCase().contains('ГУК') && !rawRoom.toUpperCase().contains('КФЕН') && !rawRoom.toUpperCase().contains('ЮНОСТЬ')) {
          report.skipped++;
          continue;
        }

        // Распознаем корпус и чистим номер
        String building = BuildingResolver.parseBuildingFromRoom(rawRoom);
        String roomNum = BuildingResolver.cleanRoomNumber(rawRoom);

        // Если префикс не найден, но это Юность
        if (building.isEmpty && rawRoom.toUpperCase().contains('ЮНОСТЬ')) {
          building = 'yunost';
          roomNum = 'Стадион';
        }

        // Если ничего не изменилось — пропускаем
        if (building == currentBuilding && roomNum == rawRoom) {
          report.skipped++;
          continue;
        }

        // Обновляем документ
        batch.update(doc.reference, {
          'room': roomNum,
          'building': building,
        });

        report.updated++;
        inBatch++;

        if (inBatch >= 400) {
          await batch.commit();
          batch = db.batch();
          inBatch = 0;
        }
      } catch (e) {
        report.errors.add('Ошибка в ${doc.id}: $e');
      }
    }

    if (inBatch > 0) {
      await batch.commit();
    }
  } catch (e) {
    report.errors.add('Критическая ошибка: $e');
  }

  return report;
}