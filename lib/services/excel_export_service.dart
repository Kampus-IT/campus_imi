// lib/services/excel_export_service.dart
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'cache_service.dart';

class ExcelExportService {
  /// Экспорт списка пользователей в Excel.
  /// Возвращает путь к файлу для шаринга.
  static Future<String> exportUsers({
    required bool includeName,
    required bool includeGroup,
    required bool includePhone,
    required bool includeEmail,
    required bool includePoints,
    required List<String> roleFilter,
    String? groupFilter,
    bool onlyStudents = false,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Студенты'];

    // Заголовки
    final headers = <String>[];
    if (includeName) headers.add('ФИО');
    if (includeGroup) headers.add('Группа');
    if (includePhone) headers.add('Телефон');
    if (includeEmail) headers.add('Email');
    if (includePoints) headers.add('Баллы ППОС');

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
          bold: true, backgroundColorHex: ExcelColor.blueGrey100);
    }

    // ✅ Сначала пробуем кэш (10 минут)
    List<Map<String, dynamic>> usersRaw;
    final cached = await CacheService.loadAdminUsers();
    if (cached.isNotEmpty && await CacheService.isAdminUsersFresh()) {
      usersRaw = cached;
    } else {
      final snapshot =
      await FirebaseFirestore.instance.collection('users').get();
      usersRaw = snapshot.docs
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .toList();
      await CacheService.saveAdminUsers(usersRaw);
    }

    int rowIndex = 1;
    for (final data in usersRaw) {
      // Фильтр по группе
      if (groupFilter != null && groupFilter.isNotEmpty) {
        if ((data['group'] ?? '') != groupFilter) continue;
      }

      // Фильтр «только студенты» (без других ролей)
      if (onlyStudents) {
        final userRoles =
            (data['roles'] as List?)?.map((e) => e.toString()).toList() ??
                <String>[];
        final globalRole = (data['role'] ?? 'student').toString();
        final hasNonStudentRole =
            userRoles.any((r) => r != 'student' && r.isNotEmpty) ||
                (globalRole != 'student' && globalRole.isNotEmpty);
        if (hasNonStudentRole) continue;
      }

      // Фильтр по конкретной роли
      if (roleFilter.isNotEmpty) {
        final userRoles =
            (data['roles'] as List?)?.map((e) => e.toString()).toList() ??
                <String>[];
        final globalRole = (data['role'] ?? 'student').toString();
        bool hasRole = false;
        for (String r in roleFilter) {
          if (userRoles.contains(r) || globalRole == r) {
            hasRole = true;
            break;
          }
        }
        if (!hasRole) continue;
      }

      int colIndex = 0;
      if (includeName) {
        sheet
            .cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex++, rowIndex: rowIndex))
            .value = TextCellValue((data['name'] ?? '').toString());
      }
      if (includeGroup) {
        sheet
            .cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex++, rowIndex: rowIndex))
            .value = TextCellValue((data['group'] ?? '').toString());
      }
      if (includePhone) {
        sheet
            .cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex++, rowIndex: rowIndex))
            .value = TextCellValue((data['phone'] ?? '').toString());
      }
      if (includeEmail) {
        sheet
            .cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex++, rowIndex: rowIndex))
            .value = TextCellValue((data['email'] ?? '').toString());
      }
      if (includePoints) {
        final points =
            int.tryParse(data['unionPoints']?.toString() ?? '0') ?? 0;
        sheet
            .cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex++, rowIndex: rowIndex))
            .value = IntCellValue(points);
      }

      rowIndex++;
    }

    // Ширина колонок
    for (int i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i, 25);
    }

    // Сохраняем файл
    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'students_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }

    return filePath;
  }

  /// Поделиться файлом через системное окно
  static Future<void> shareFile(String filePath) async {
    final file = XFile(filePath);
    await Share.shareXFiles([file], text: 'Экспорт студентов СВФУ Кампус');
  }
}