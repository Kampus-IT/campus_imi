// lib/screens/admin_departments_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/department_model.dart';
import '../services/cache_service.dart';

class AdminDepartmentsScreen extends StatefulWidget {
  const AdminDepartmentsScreen({super.key});

  @override
  State<AdminDepartmentsScreen> createState() =>
      _AdminDepartmentsScreenState();
}

class _AdminDepartmentsScreenState extends State<AdminDepartmentsScreen> {
  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  String _type = 'institute';
  bool _isAdding = false;

  List<Department>? _departments;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments({bool forceRefresh = false}) async {
    final cached = await CacheService.loadAdminDepartments();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _departments = cached
            .map((m) => Department.fromMap(m['id'] as String? ?? '', m))
            .toList();
      });
    }

    final isFresh = await CacheService.isAdminDepartmentsFresh();
    if (isFresh && cached.isNotEmpty && !forceRefresh) return;

    if (mounted) setState(() => _isRefreshing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('departments')
          .orderBy('shortName')
          .get();
      final raw = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      await CacheService.saveAdminDepartments(raw);
      if (mounted) {
        setState(() {
          _departments = snap.docs
              .map((d) => Department.fromMap(d.id, d.data()))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки подразделений: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить подразделения')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _onRefresh() async {
    await CacheService.invalidateAdminDepartments();
    await _loadDepartments(forceRefresh: true);
  }

  Future<void> _addDepartment() async {
    if (_nameController.text.trim().isEmpty ||
        _shortNameController.text.trim().isEmpty) {
      return;
    }

    setState(() => _isAdding = true);
    try {
      final docId = _shortNameController.text
          .trim()
          .replaceAll(' ', '')
          .toUpperCase();

      await FirebaseFirestore.instance
          .collection('departments')
          .doc(docId)
          .set({
        'name': _nameController.text.trim(),
        'shortName': _shortNameController.text.trim(),
        'type': _type,
      });

      _nameController.clear();
      _shortNameController.clear();
      await CacheService.invalidateAdminDepartments();
      await _loadDepartments(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Подразделение добавлено'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _showEditDialog(Department dept) {
    final nameCtrl = TextEditingController(text: dept.name);
    final shortCtrl = TextEditingController(text: dept.shortName);
    String currentType = dept.type;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Редактировать подразделение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration:
                  const InputDecoration(labelText: 'Полное название')),
              const SizedBox(height: 12),
              TextField(
                  controller: shortCtrl,
                  decoration:
                  const InputDecoration(labelText: 'Аббревиатура')),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: currentType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'institute', child: Text('Институт')),
                  DropdownMenuItem(value: 'faculty', child: Text('Факультет')),
                  DropdownMenuItem(value: 'college', child: Text('Колледж')),
                ],
                onChanged: (v) => setDialogState(() => currentType = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('departments')
                    .doc(dept.id)
                    .update({
                  'name': nameCtrl.text.trim(),
                  'shortName': shortCtrl.text.trim(),
                  'type': currentType,
                });
                await CacheService.invalidateAdminDepartments();
                if (context.mounted) Navigator.pop(context);
                await _loadDepartments(forceRefresh: true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDepartment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подразделение?'),
        content: const Text(
            'Внимание: Группы, привязанные к этому подразделению, потеряют связь.'),
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
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('departments')
          .doc(id)
          .delete();
      await CacheService.invalidateAdminDepartments();
      await _loadDepartments(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подразделения СВФУ')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: 'Полное название (Институт математики...)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _shortNameController,
                        decoration: const InputDecoration(
                            labelText: 'Аббревиатура (ИМИ)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _type,
                      items: const [
                        DropdownMenuItem(
                            value: 'institute', child: Text('Институт')),
                        DropdownMenuItem(
                            value: 'faculty', child: Text('Факультет')),
                        DropdownMenuItem(
                            value: 'college', child: Text('Колледж')),
                      ],
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAdding ? null : _addDepartment,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy),
                    child: _isAdding
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Добавить подразделение',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _departments == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _onRefresh,
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final docs = _departments!;
    if (docs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 64),
            child:
            Center(child: Text('Подразделений пока нет. Добавьте первое.')),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final dept = docs[i];
        IconData icon;
        if (dept.type == 'college') {
          icon = Icons.school;
        } else if (dept.type == 'faculty') {
          icon = Icons.account_balance;
        } else {
          icon = Icons.apartment;
        }

        return ListTile(
          leading: Icon(icon, color: AppTheme.primaryNavy),
          title: Text(dept.name),
          subtitle: Text('${dept.shortName} · ${dept.type}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: AppTheme.accentBlue),
                onPressed: () => _showEditDialog(dept),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteDepartment(dept.id),
              ),
            ],
          ),
        );
      },
    );
  }
}