// lib/screens/admin_import_schedule_screen.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/excel_schedule_parser.dart';
import '../services/schedule_import_service.dart';
import '../services/svfu_schedule_service.dart';
import '../theme/app_theme.dart';
import '../models/department_model.dart';
import '../widgets/app_ui.dart';

class AdminImportScheduleScreen extends StatefulWidget {
  const AdminImportScheduleScreen({super.key});

  @override
  State<AdminImportScheduleScreen> createState() =>
      _AdminImportScheduleScreenState();
}

class _AdminImportScheduleScreenState extends State<AdminImportScheduleScreen> {
  // --- Состояние для Excel ---
  bool _parsing = false;
  bool _importing = false;
  ExcelParseResult? _result;
  String? _fileName;
  int _done = 0;
  int _total = 0;
  String? _selectedDeptId;

  // --- Состояние для СВФУ ---
  final SvfuScheduleService _svfuService = SvfuScheduleService();
  bool _isSyncing = false;
  bool _isLoadingGroups = true;
  List<SvfuGroup> _allGroups = [];
  SvfuGroup? _selectedGroup;

  // --- Список уникальных кодов факультетов ---
  List<String> _availableFaculties = [];

  // --- Состояние для синхронизации факультета ---
  bool _isSyncingFaculty = false;
  String _currentSyncingGroup = '';
  int _facultyDone = 0;
  int _facultyTotal = 0;

  // --- Состояние для миграции подгрупп ---
  bool _isMigratingSubgroups = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _svfuService.getAllGroups();
      if (mounted) {
        final codes = <String>{};
        for (final g in groups) {
          final parts = g.name.split('-');
          if (parts.isNotEmpty && parts.first.isNotEmpty) {
            codes.add(parts.first);
          }
        }
        final sortedCodes = codes.toList()..sort();

        setState(() {
          _allGroups = groups;
          _availableFaculties = sortedCodes;
          _isLoadingGroups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGroups = false);
        _snack('Не удалось загрузить список групп: $e', error: true);
      }
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ✅ Обновление подгрупп в уже существующей базе
  Future<void> _migrateSubgroups() async {
    setState(() => _isMigratingSubgroups = true);
    _snack('⏳ Обновляем подгруппы в базе...');

    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db.collection('lessons').get();

      int updated = 0;
      final batch = db.batch();
      int count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final subject = (data['subject'] ?? '').toString();

        final subMatch = RegExp(r'([12])\s*(?:пг|п/г|пр|пн)', caseSensitive: false).firstMatch(subject);

        if (subMatch != null) {
          final subgroup = int.tryParse(subMatch.group(1) ?? '');
          final cleanSubject = subject.replaceAll(subMatch.group(0)!, '').replaceAll(RegExp(r'[,\.]\s*$'), '').trim();

          batch.update(doc.reference, {
            'subgroup': subgroup,
            'subject': cleanSubject,
          });

          updated++;
          count++;

          if (count >= 400) {
            await batch.commit();
            count = 0;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      if (count > 0) await batch.commit();

      if (mounted) _snack('✅ Обновлено $updated пар. Подгруппы работают!');
    } catch (e) {
      if (mounted) _snack('❌ Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _isMigratingSubgroups = false);
    }
  }

  Future<void> _syncFromSvfu() async {
    if (_selectedDeptId == null) {
      _snack('Выберите подразделение (институт)', error: true);
      return;
    }
    if (_selectedGroup == null) {
      _snack('Выберите группу из списка', error: true);
      return;
    }

    setState(() { _isSyncing = true; _done = 0; _total = 0; });
    try {
      final count = await _svfuService.importGroupSchedule(
        groupId: _selectedGroup!.id,
        groupName: _selectedGroup!.name,
        departmentId: _selectedDeptId!,
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; });
        },
      );
      if (mounted) _snack('✅ Загружено $count пар для ${_selectedGroup!.cleanName}');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncFaculty() async {
    if (_selectedDeptId == null) {
      _snack('Выберите подразделение (институт)', error: true);
      return;
    }

    final facultyCode = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Синхронизация всего факультета'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Выберите факультет для синхронизации всех его групп.\n\n'
                        '⚠️ Это займёт 10–30 минут, в зависимости от количества групп.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Факультет',
                      border: OutlineInputBorder(),
                    ),
                    value: selected,
                    isExpanded: true,
                    items: _availableFaculties.map((code) => DropdownMenuItem(
                      value: code,
                      child: Text(code),
                    )).toList(),
                    onChanged: (v) => setStateDialog(() => selected = v),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                ElevatedButton(
                  onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
                  child: const Text('Синхронизировать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (facultyCode == null) return;

    setState(() {
      _isSyncingFaculty = true;
      _facultyDone = 0;
      _facultyTotal = 0;
      _currentSyncingGroup = '';
    });

    try {
      final count = await _svfuService.importFacultySchedule(
        facultyCode: facultyCode,
        departmentId: _selectedDeptId!,
        onProgress: (done, total, groupName) {
          if (mounted) {
            setState(() {
              _facultyDone = done;
              _facultyTotal = total;
              _currentSyncingGroup = groupName;
            });
          }
        },
      );
      if (mounted) _snack('✅ Импортировано $count пар для факультета $facultyCode');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _isSyncingFaculty = false);
    }
  }

  // --- Excel импорт ---
  Future<void> _pickExcel() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null) { _snack('Не удалось прочитать файл', error: true); return; }

      setState(() { _parsing = true; _result = null; _fileName = res.files.first.name; });
      final result = ExcelScheduleParser.parse(bytes);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _importExcel() async {
    if (_selectedDeptId == null) { _snack('Выберите подразделение', error: true); return; }
    final res = _result;
    if (res == null || res.lessons.isEmpty) { _snack('Нет данных для импорта', error: true); return; }

    setState(() { _importing = true; _done = 0; _total = res.lessons.length; });
    try {
      final count = await ScheduleImportService().importLessons(
        res.lessons,
        onProgress: (done, total) {
          if (mounted) setState(() { _done = done; _total = total; });
        },
      );
      if (mounted) _snack('✅ Импортировано $count пар');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Импорт расписания')),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDepartmentSelector(theme),
          const SizedBox(height: 16),

          // --- Импорт из СВФУ ---
          _buildSectionTitle('Импорт из API СВФУ'),
          const SizedBox(height: 8),
          if (_isLoadingGroups)
            const Center(child: CircularProgressIndicator())
          else ...[
            _buildGroupSelector(theme),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _syncFromSvfu,
                    icon: _isSyncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(_isSyncing ? '$_done / $_total' : 'Импортировать группу'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSyncingFaculty ? null : _syncFaculty,
                    icon: _isSyncingFaculty
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.school),
                    label: Text(_isSyncingFaculty ? '$_facultyDone / $_facultyTotal' : 'Импортировать факультет'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isSyncingFaculty && _currentSyncingGroup.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Группа: $_currentSyncingGroup', style: const TextStyle(fontSize: 12)),
          ],

          const Divider(height: 32),

          // --- Импорт из Excel ---
          _buildSectionTitle('Импорт из Excel'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _parsing ? null : _pickExcel,
            icon: _parsing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file),
            label: Text(_fileName ?? 'Выбрать .xlsx'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 12),
            Text('Найдено ${_result!.lessons.length} пар', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_result!.errors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Ошибок: ${_result!.errors.length}', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _importing ? null : _importExcel,
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_importing ? '$_done / $_total' : 'Импортировать в базу'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],

          const Divider(height: 32),

          // --- Миграция подгрупп ---
          _buildSectionTitle('Обслуживание базы'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _isMigratingSubgroups ? null : _migrateSubgroups,
            icon: _isMigratingSubgroups
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cleaning_services),
            label: const Text('Обновить подгруппы в базе'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: appMutedColor(context)));
  }

  Widget _buildDepartmentSelector(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final depts = snapshot.data!.docs.map((d) => Department.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Подразделение (институт)', border: OutlineInputBorder()),
          value: _selectedDeptId,
          items: depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.shortName))).toList(),
          onChanged: (v) => setState(() => _selectedDeptId = v),
        );
      },
    );
  }

  Widget _buildGroupSelector(ThemeData theme) {
    final filtered = _allGroups.where((g) => g.name.isNotEmpty).toList();
    return DropdownButtonFormField<SvfuGroup>(
      decoration: const InputDecoration(labelText: 'Группа', border: OutlineInputBorder()),
      value: _selectedGroup,
      isExpanded: true,
      items: filtered.take(500).map((g) => DropdownMenuItem(
        value: g,
        child: Text('${g.cleanName} (${g.course} курс)'),
      )).toList(),
      onChanged: (v) => setState(() => _selectedGroup = v),
    );
  }
}