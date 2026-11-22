// lib/screens/admin_schedule_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/lesson.dart';
import '../services/firestore_service.dart';
import '../services/cache_service.dart';
import 'add_schedule_screen.dart';
import 'admin_import_schedule_screen.dart'; // ✅ Импорт экрана импорта

class AdminScheduleScreen extends StatefulWidget {
  const AdminScheduleScreen({super.key});

  @override
  State<AdminScheduleScreen> createState() => _AdminScheduleScreenState();
}

class _AdminScheduleScreenState extends State<AdminScheduleScreen> {
  final _firestoreService = FirestoreService();

  List<Lesson>? _allLessons;
  List<String> _uniqueGroups = [];
  String? _selectedGroup;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons({bool forceRefresh = false}) async {
    final cached = await CacheService.loadAdminLessons();
    if (cached.isNotEmpty && mounted) {
      final lessons = cached
          .map((m) => Lesson.fromMap(m['id'] as String? ?? '', m))
          .toList();
      final groups = lessons.map((l) => l.group).toSet().toList()..sort();
      setState(() {
        _allLessons = lessons;
        _uniqueGroups = groups.isEmpty ? ['Б-ПИГМУ-24'] : groups;
        if (_selectedGroup == null || !_uniqueGroups.contains(_selectedGroup)) {
          _selectedGroup = _uniqueGroups.first;
        }
        _isLoading = false;
      });
    }

    final isFresh = await CacheService.isAdminLessonsFresh();
    if (isFresh && cached.isNotEmpty && !forceRefresh) return;

    if (mounted) setState(() => _isRefreshing = true);
    try {
      final lessons = await _firestoreService.getAllLessonsOnce();
      final groups = lessons.map((l) => l.group).toSet().toList()..sort();
      if (groups.isEmpty) groups.add('Б-ПИГМУ-24');

      await CacheService.saveAdminLessons(
        lessons.map((l) => {'id': l.id, ...l.toMap()}).toList(),
      );

      if (mounted) {
        setState(() {
          _allLessons = lessons;
          _uniqueGroups = groups;
          if (_selectedGroup == null ||
              !_uniqueGroups.contains(_selectedGroup)) {
            _selectedGroup = _uniqueGroups.first;
          }
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки расписания: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _onRefresh() async {
    await CacheService.invalidateAdminLessons();
    await _loadLessons(forceRefresh: true);
  }

  Future<void> _openEditor({Lesson? lesson}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(lesson: lesson),
      ),
    );
    if (result == true) {
      await CacheService.invalidateAdminLessons();
      await _loadLessons(forceRefresh: true);
    }
  }

  Future<void> _openImportScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminImportScheduleScreen(),
      ),
    );
    if (result == true) {
      await CacheService.invalidateAdminLessons();
      await _loadLessons(forceRefresh: true);
    }
  }

  Future<void> _confirmDelete(Lesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить занятие?'),
        content: Text(
            '${lesson.subject}\n${lesson.group} · ${lesson.time}\n\nЭто действие нельзя отменить.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _firestoreService.deleteLesson(lesson.id);
      await CacheService.invalidateAdminLessons();
      await _loadLessons(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          // ✅ КНОПКА ИМПОРТА
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Импорт расписания',
            onPressed: _openImportScreen,
          ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Не удалось загрузить данные'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _loadLessons(forceRefresh: true);
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedGroup,
                  isExpanded: true,
                  items: _uniqueGroups
                      .map((g) =>
                      DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedGroup = v),
                ),
              ),
              const SizedBox(width: 12),
              // ✅ Кнопка "Добавить" (ручное)
              ElevatedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: _buildLessonsList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLessonsList() {
    if (_selectedGroup == null || _allLessons == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 100)],
      );
    }

    final lessons = _allLessons!
        .where((l) => l.group == _selectedGroup)
        .toList()
      ..sort((a, b) {
        if (a.dayIndex != b.dayIndex) {
          return a.dayIndex.compareTo(b.dayIndex);
        }
        return a.time.compareTo(b.time);
      });

    if (lessons.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: Text('Для этой группы пар пока нет')),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: lessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final lesson = lessons[i];
        return Card(
          child: ListTile(
            title: Text(lesson.subject,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${lesson.teacher} · ${lesson.room}\n${_dayName(lesson.dayIndex)} · ${lesson.time}'),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: AppTheme.accentBlue),
                  onPressed: () => _openEditor(lesson: lesson),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(lesson),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _dayName(int dayIndex) {
    const days = [
      'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота',
    ];
    if (dayIndex < 0 || dayIndex >= days.length) return '';
    return days[dayIndex];
  }
}