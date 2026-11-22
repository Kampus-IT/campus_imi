// lib/screens/admin_users_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/user_model.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _searchQuery = '';
  String _roleFilter = 'Все';

  List<String> _allGroups = [];
  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('groups').orderBy('name').get();
      final groups = snap.docs.map((d) => d.id).toList();
      if (mounted) {
        setState(() {
          _allGroups = groups;
          _isLoadingGroups = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки групп: $e');
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  Future<void> _showEditDialog(UserModel user) async {
    String selectedRole = user.role.value;
    String selectedGroup = user.group;

    final newGroup = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать студента'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${user.name} (${user.email})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Роль'),
              value: selectedRole,
              items: const [
                DropdownMenuItem(value: 'student', child: Text('Студент')),
                DropdownMenuItem(value: 'activist', child: Text('Активист')),
                DropdownMenuItem(value: 'admin', child: Text('Администратор')),
              ],
              onChanged: (v) => selectedRole = v!,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Группа'),
              value: _allGroups.contains(selectedGroup) ? selectedGroup : null,
              items: _allGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => selectedGroup = v!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selectedGroup),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newGroup != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'group': newGroup,
          'role': selectedRole,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Данные обновлены'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Студенты')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск по имени или группе',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Фильтр по роли',
                    border: OutlineInputBorder(),
                  ),
                  value: _roleFilter,
                  items: const [
                    DropdownMenuItem(value: 'Все', child: Text('Все')),
                    DropdownMenuItem(value: 'student', child: Text('Студенты')),
                    DropdownMenuItem(value: 'activist', child: Text('Активисты')),
                    DropdownMenuItem(value: 'admin', child: Text('Администраторы')),
                  ],
                  onChanged: (v) => setState(() => _roleFilter = v!),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Ошибка: ${snapshot.error}'));
                }

                var docs = snapshot.data!.docs;
                var users = docs.map((d) => UserModel.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

                if (_searchQuery.isNotEmpty) {
                  users = users.where((u) =>
                  u.name.toLowerCase().contains(_searchQuery) ||
                      u.group.toLowerCase().contains(_searchQuery)
                  ).toList();
                }

                if (_roleFilter != 'Все') {
                  users = users.where((u) => u.role.value == _roleFilter).toList();
                }

                if (users.isEmpty) {
                  return const Center(child: Text('Пользователи не найдены'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final user = users[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
                        child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${user.email}\nГруппа: ${user.group} · Роль: ${user.role.label}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: AppTheme.accentBlue),
                        onPressed: () => _showEditDialog(user),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}