import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/excel_schedule_parser.dart';
import '../services/schedule_import_service.dart';
import '../services/svfu_schedule_service.dart';
import '../theme/app_theme.dart';
import '../models/department_model.dart';

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

  // ✅ НОВЫЙ МЕТОД: Обновление подгрупп в уже существующей базе
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

        // Ищем "1пг", "2пг", "п/г 1" и т.д.
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
                  child: const Text('Начать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (facultyCode == null || facultyCode.isEmpty) return;

    setState(() {
      _isSyncingFaculty = true;
      _currentSyncingGroup = 'Подготовка...';
      _facultyDone = 0;
      _facultyTotal = 0;
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
      if (mounted) _snack('✅ Факультет $facultyCode: загружено $count пар');
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingFaculty = false;
          _currentSyncingGroup = '';
        });
      }
    }
  }

  // --- Excel методы ---
  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;

    setState(() { _parsing = true; _result = null; _fileName = picked.files.single.name; });

    try {
      final bytes = picked.files.single.bytes!;
      final result = await Future.microtask(
            () => ExcelScheduleParser.parse(Uint8List.fromList(bytes)),
      );
      if (!mounted) return;
      setState(() { _result = result; _parsing = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _parsing = false);
      _snack('Ошибка чтения файла: $e', error: true);
    }
  }

  Future<void> _import() async {
    final r = _result;
    if (r == null || r.lessons.isEmpty) return;
    if (_selectedDeptId == null) {
      _snack('Пожалуйста, выберите подразделение для этих групп', error: true);
      return;
    }

    setState(() { _importing = true; _done = 0; _total = r.lessons.length; });

    try {
      final count = await ScheduleImportService().importLessons(
        r.lessons,
        onProgress: (d, t) {
          if (mounted) setState(() { _done = d; _total = t; });
        },
      );

      final uniqueGroups = r.lessons.map((l) => l.group).toSet();
      for (String groupName in uniqueGroups) {
        final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupName);
        final existingDoc = await groupRef.get();
        if (existingDoc.exists && existingDoc.data()?['departmentId'] != null) continue;
        await groupRef.set({
          'name': groupName,
          'departmentId': _selectedDeptId,
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      _snack('Импортировано $count пар. Группы привязаны к подразделению.');
      setState(() { _importing = false; _result = null; _fileName = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack('Ошибка импорта: $e', error: true);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red : AppTheme.primaryNavy,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт расписания')),
      backgroundColor: AppTheme.backgroundGray,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== БЛОК СВФУ =====
          Card(
            color: Colors.blue.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.blueAccent),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('🔥 Автоматическая синхронизация',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                  const SizedBox(height: 8),
                  const Text('Скачивает актуальное расписание напрямую с сайта СВФУ.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 16),

                  // 1. Выбор подразделения
                  const Text('1. Выберите подразделение',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      final depts = snapshot.data!.docs.map((d) =>
                          Department.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Подразделение',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        value: _selectedDeptId,
                        isExpanded: true,
                        items: depts.map((d) => DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.shortName} (${d.name})',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedDeptId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Выбор группы
                  const Text('2. Выберите группу (для одной группы)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),

                  if (_isLoadingGroups)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ))
                  else ...[
                    Autocomplete<SvfuGroup>(
                      displayStringForOption: (g) => g.cleanName,
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _allGroups.take(10);
                        return _allGroups.where((g) =>
                            g.cleanName.toLowerCase().contains(textEditingValue.text.toLowerCase())
                        );
                      },
                      onSelected: (g) => setState(() => _selectedGroup = g),
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Поиск группы (например, Б-ПИГМУ-24)',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: Icon(Icons.search),
                          ),
                        );
                      },
                    ),

                    if (_selectedGroup != null) ...[
                      const SizedBox(height: 8),
                      Text('Выбрано: ${_selectedGroup!.cleanName} (ID: ${_selectedGroup!.id})',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ],

                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isSyncing || _isSyncingFaculty || _isMigratingSubgroups || _selectedGroup == null || _selectedDeptId == null
                          ? null
                          : _syncFromSvfu,
                      icon: _isSyncing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_download),
                      label: Text(_isSyncing
                          ? (_total == 0 ? 'Синхронизация...' : 'День $_done из $_total')
                          : 'Синхронизировать выбранную группу'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),

                    // 3. Синхронизация факультета
                    const Text('3. Или синхронизировать весь факультет',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: (_isSyncing || _isSyncingFaculty || _isMigratingSubgroups || _selectedDeptId == null)
                          ? null
                          : _syncFaculty,
                      icon: _isSyncingFaculty
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.school),
                      label: Text(_isSyncingFaculty
                          ? '$_currentSyncingGroup ($_facultyDone из $_facultyTotal)'
                          : 'Синхронизировать весь факультет'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    // 4. Миграция подгрупп
                    const Text('4. Обновить старые данные (без скачивания)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isSyncing || _isSyncingFaculty || _isMigratingSubgroups
                          ? null
                          : _migrateSubgroups,
                      icon: _isMigratingSubgroups
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_fix_high),
                      label: Text(_isMigratingSubgroups
                          ? 'Обновление...'
                          : 'Обновить подгруппы в базе'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // ===== БЛОК EXCEL =====
          const Text('Резервный импорт из Excel',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          const Text('Используйте, если API СВФУ недоступно.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 16),

          const Text('1. К какому подразделению относятся эти группы?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final depts = snapshot.data!.docs.map((d) =>
                  Department.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Подразделение',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: AppTheme.cardWhite,
                ),
                value: _selectedDeptId,
                isExpanded: true,
                items: depts.map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text('${d.shortName} (${d.name})',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _selectedDeptId = v),
              );
            },
          ),
          const SizedBox(height: 24),

          const Text('2. Выберите файл .xlsx',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _parsing || _importing ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName ?? 'Выбрать файл'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
          ),

          if (_parsing)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildSummary(_result!),
            const SizedBox(height: 12),
            if (_result!.lessons.isNotEmpty) ...[
              if (_importing)
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _importing ? null : _import,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_importing
                    ? 'Импорт $_done/$_total…'
                    : 'Импортировать ${_result!.lessons.length} пар'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(ExcelParseResult r) {
    final groups = r.lessons.map((l) => l.group).toSet().toList()..sort();
    const _daysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Распознано пар: ${r.lessons.length}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Группы (${groups.length}): ${groups.join(", ")}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
            if (r.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Ошибок: ${r.errors.length}', style: const TextStyle(color: Colors.red)),
              ...r.errors.take(8).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
            ],
            const SizedBox(height: 12),
            const Text('Первые 10 пар:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            ...r.lessons.take(10).map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${l.group} · ${_daysShort[l.dayIndex]} · '
                    '${l.week == 0 ? "кажд." : l.week == 1 ? "нечёт." : "чёт."} · '
                    '${l.time} · ${l.subject}',
                style: const TextStyle(fontSize: 12),
              ),
            )),
          ],
        ),
      ),
    );
  }
}