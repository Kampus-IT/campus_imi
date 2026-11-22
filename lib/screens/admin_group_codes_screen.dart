// lib/screens/admin_group_codes_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class AdminGroupCodesScreen extends StatefulWidget {
  const AdminGroupCodesScreen({super.key});

  @override
  State<AdminGroupCodesScreen> createState() => _AdminGroupCodesScreenState();
}

class _AdminGroupCodesScreenState extends State<AdminGroupCodesScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedDeptFilter; // null — все институты

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Код "$code" скопирован в буфер обмена'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Диалоговое окно для изменения кода группы вручную
  Future<void> _editGroupCode(BuildContext context, String docId, String groupName, String currentCode) async {
    final controller = TextEditingController(text: currentCode);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Изменить код группы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Группа: $groupName', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Секретный код',
                hintText: 'Введите новый код',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final newCode = controller.text.trim().toUpperCase();
              if (newCode.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Код не может быть пустым'), backgroundColor: AppTheme.danger),
                );
                return;
              }

              try {
                // Проверяем, не занят ли этот код другой группой
                final check = await FirebaseFirestore.instance
                    .collection('groups')
                    .where('code', isEqualTo: newCode)
                    .get();

                if (check.docs.isNotEmpty && check.docs.first.id != docId) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Этот код уже используется другой группой!'), backgroundColor: AppTheme.danger),
                    );
                  }
                  return;
                }

                // Обновляем код в Firestore
                await FirebaseFirestore.instance.collection('groups').doc(docId).update({
                  'code': newCode,
                });

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Код для группы "$groupName" успешно изменён!')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: AppTheme.danger),
                  );
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Секретные коды групп'),
      ),
      body: Column(
        children: [
          // 🔎 Панель поиска и фильтрации
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                // Текстовое поле поиска
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Поиск по названию или коду...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                        : null,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Выпадающий список фильтра по институтам (departments)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
                  builder: (context, deptSnapshot) {
                    final deptDocs = deptSnapshot.data?.docs ?? [];

                    return DropdownButtonFormField<String?>(
                      value: _selectedDeptFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Фильтр по институту',
                        prefixIcon: Icon(Icons.apartment_outlined),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Все институты'),
                        ),
                        ...deptDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final deptId = doc.id; // например, 'ИМИ'
                          final deptName = data['shortName'] ?? deptId;
                          return DropdownMenuItem<String?>(
                            value: deptId,
                            child: Text(deptName),
                          );
                        }),
                      ],
                      onChanged: (val) => setState(() => _selectedDeptFilter = val),
                    );
                  },
                ),
              ],
            ),
          ),

          // 📋 Список групп с фильтрацией на клиенте
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('groups').orderBy('name').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const AppErrorState(message: 'Не удалось загрузить группы');
                }

                final docs = snapshot.data?.docs ?? [];

                // Применяем фильтры (поиск и институт)
                final filteredDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final groupName = (data['name'] ?? '').toString().toLowerCase();
                  final code = (data['code'] ?? '').toString().toLowerCase();
                  final deptId = (data['departmentId'] ?? '').toString();

                  // Фильтр по институту
                  if (_selectedDeptFilter != null && deptId != _selectedDeptFilter) {
                    return false;
                  }

                  // Фильтр по поисковому запросу (название группы или код)
                  if (_searchQuery.isNotEmpty) {
                    final matchName = groupName.contains(_searchQuery);
                    final matchCode = code.contains(_searchQuery);
                    if (!matchName && !matchCode) return false;
                  }

                  return true;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'Ничего не найдено',
                    message: 'По вашему запросу или фильтру нет групп',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.s16),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppTheme.s8),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final groupName = data['name'] ?? 'Без названия';
                    final code = data['code'] ?? 'Не задан';
                    final deptId = data['departmentId'] ?? '';

                    return AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      onTap: () => _editGroupCode(context, doc.id, groupName, code),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.group_outlined, color: AppTheme.primaryNavy, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  groupName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                if (deptId.isNotEmpty)
                                  Text(
                                    'Институт: $deptId · Нажмите для изм.',
                                    style: TextStyle(fontSize: 12, color: appMutedColor(context)),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Color(0xFF8A5A00),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _copyToClipboard(context, code),
                                  child: const Icon(Icons.copy, size: 16, color: Color(0xFF8A5A00)),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit, size: 16, color: Color(0xFF8A5A00)),
                              ],
                            ),
                          ),
                        ],
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