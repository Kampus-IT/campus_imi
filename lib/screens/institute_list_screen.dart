// lib/screens/institute_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/institute_info.dart';
import '../services/cache_service.dart';
import '../theme/app_theme.dart';
import 'guest_screen.dart';

class InstituteListScreen extends StatefulWidget {
  const InstituteListScreen({super.key});

  @override
  State<InstituteListScreen> createState() => _InstituteListScreenState();
}

class _InstituteListScreenState extends State<InstituteListScreen> {
  String _search = '';
  List<InstituteInfo>? _cachedInstitutes;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadInstitutes();
  }

  Future<void> _loadInstitutes({bool forceRefresh = false}) async {
    final cached = await CacheService.loadInstitutes();
    if (cached.isNotEmpty && mounted) {
      setState(() => _cachedInstitutes = cached);
    }

    final isFresh = await CacheService.isInstitutesFresh();
    if (isFresh && cached.isNotEmpty && !forceRefresh) return;

    if (mounted) setState(() => _isRefreshing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('departments')
          .get();
      final fresh = snap.docs
          .map((d) => InstituteInfo.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.shortName.compareTo(b.shortName));
      await CacheService.saveInstitutes(fresh);
      await CacheService.saveInstitutesTime();
      if (mounted) setState(() => _cachedInstitutes = fresh);
    } catch (e) {
      debugPrint('Ошибка загрузки институтов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить список')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _onRefresh() async {
    await CacheService.invalidateInstitutes();
    await _loadInstitutes(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Выбор института'),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск института...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) =>
                  setState(() => _search = v.toLowerCase()),
            ),
          ),
          if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _cachedInstitutes == null
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
    var docs = _cachedInstitutes!;
    if (_search.isNotEmpty) {
      docs = docs.where((d) {
        return d.name.toLowerCase().contains(_search) ||
            d.shortName.toLowerCase().contains(_search);
      }).toList();
    }

    if (docs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: Text('Институты пока не добавлены')),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final info = docs[i];
        final isWorking = info.shortName.toUpperCase() == 'ИМИ';
        final statusText = isWorking ? 'Приложение работает' : 'Скоро';
        final statusColor = isWorking ? Colors.green : Colors.grey;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: info.logoUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                info.logoUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.school,
                    color: Theme.of(context).colorScheme.primary,
                    size: 40),
              ),
            )
                : Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.school,
                  color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(info.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${info.shortName}\n$statusText',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: statusColor),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GuestScreen(
                  instituteId: info.shortName,
                  instituteName: info.shortName,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}