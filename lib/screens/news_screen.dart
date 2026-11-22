// lib/screens/news_screen.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/news_model.dart';
import '../services/cache_service.dart';
import '../services/news_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'add_news_screen.dart';
import 'news_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  final bool embedded;
  const NewsScreen({super.key, this.embedded = false});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with AutomaticKeepAliveClientMixin {
  final NewsService _newsService = NewsService();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  final Map<String, String> _selectedCategories = {
    'university': 'Все',
    'institute': 'Все',
    'profkom': 'Все',
  };

  String? _userDeptId;
  bool _isAdmin = false;

  List<News>? _cachedNews;
  bool _isRefreshing = false;

  final Map<String, List<String>> _categoriesMap = {
    'university': ['Все', 'Спорт', 'Культура', 'Конференции', 'Мероприятия'],
    'institute': ['Все', 'Объявления', 'События', 'Мероприятия'],
    'profkom': ['Все', 'Мероприятия', 'Новости'],
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checkUser();
    _loadNews();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _isAdmin = doc.data()?['role'] == 'admin';
          _userDeptId = doc.data()?['departmentId'];
        });
      }
    }
  }

  /// Загрузка новостей с кэшем и лимитом (только 30 последних из сети)
  Future<void> _loadNews({bool forceRefresh = false}) async {
    // 1. Мгновенно показываем кэш
    final cached = await CacheService.loadNews();
    if (cached.isNotEmpty && mounted) {
      setState(() => _cachedNews = cached);
    }

    // 2. Если кэш свежий (15 минут) — не идем в сеть
    final isFresh = await CacheService.isNewsFresh();
    if (isFresh && cached.isNotEmpty && !forceRefresh) {
      return;
    }

    // 3. Идем в сеть, но только за 30 последними
    if (mounted) setState(() => _isRefreshing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('news')
          .orderBy('createdAt', descending: true)
          .limit(30) // ✅ ЛИМИТ
          .get();

      final fresh = snap.docs.map((d) => News.fromMap(d.data(), d.id)).toList();

      // 4. Сливаем с кэшем
      final merged = await CacheService.loadNewsMerged(fresh);

      await CacheService.saveNewsTime();
      if (mounted) setState(() => _cachedNews = merged);
    } catch (e) {
      debugPrint('Ошибка загрузки новостей: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить новости')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _onRefresh() async {
    await CacheService.invalidateNews();
    await _loadNews(forceRefresh: true);
  }

  Future<void> _showOptionsDialog(News news) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppTheme.accentBlue),
              title: const Text('Редактировать'),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddNewsScreen(news: news)),
                );
                if (result == true && mounted) {
                  await CacheService.invalidateNews();
                  _loadNews(forceRefresh: true);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title:
              const Text('Удалить', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить новость?'),
                    content: const Text('Это действие нельзя отменить.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _newsService.deleteNews(news.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Новость удалена'),
                          backgroundColor: Colors.green),
                    );
                    await CacheService.invalidateNews();
                    _loadNews(forceRefresh: true);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          leading: widget.embedded
              ? null
              : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Новости'),
          actions: [
            if (_isAdmin)
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddNewsScreen()),
                  );
                  if (mounted) {
                    await CacheService.invalidateNews();
                    _loadNews(forceRefresh: true);
                  }
                },
              ),
          ],
          bottom: const TabBar(
            labelColor: AppTheme.accentBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.accentBlue,
            tabs: [
              Tab(text: 'СВФУ'),
              Tab(text: 'Мой институт'),
              Tab(text: 'Профсоюз'),
            ],
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск по всем новостям...',
                  prefixIcon:
                  Icon(Icons.search, color: appMutedColor(context)),
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
            ),
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTabContent('university'),
                  _buildTabContent('institute'),
                  _buildTabContent('profkom'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(String scope) {
    final categories = _categoriesMap[scope] ?? ['Все'];
    final selectedCategory = _selectedCategories[scope] ?? 'Все';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: categories.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: c,
                    selected: selectedCategory == c,
                    onTap: () =>
                        setState(() => _selectedCategories[scope] = c),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _cachedNews == null
              ? const Center(child: CircularProgressIndicator())
              : _buildNewsList(scope, selectedCategory),
        ),
      ],
    );
  }

  Widget _buildNewsList(String scope, String selectedCategory) {
    var newsList = List<News>.from(_cachedNews!);
    newsList = newsList.where((n) => n.scope == scope).toList();

    if (scope == 'institute' && _userDeptId != null) {
      newsList = newsList
          .where((n) =>
      n.departmentId == _userDeptId || n.departmentId.isEmpty)
          .toList();
    }

    if (selectedCategory != 'Все') {
      newsList =
          newsList.where((n) => n.category == selectedCategory).toList();
    }

    if (_searchQuery.isNotEmpty) {
      newsList = newsList
          .where((n) =>
      n.title.toLowerCase().contains(_searchQuery) ||
          n.body.toLowerCase().contains(_searchQuery))
          .toList();
    }

    if (newsList.isEmpty) {
      return AppEmptyState(
        icon: Icons.newspaper_outlined,
        title: 'Здесь пока пусто',
        message: _searchQuery.isNotEmpty || selectedCategory != 'Все'
            ? 'Попробуйте изменить поиск или категорию'
            : 'Новости этого раздела скоро появятся',
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: newsList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final news = newsList[i];
          return GestureDetector(
            onLongPress: _isAdmin ? () => _showOptionsDialog(news) : null,
            child: _NewsCard(
              news: news,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => NewsDetailScreen(news: news)),
              ).then((_) => setState(() {})),
            ),
          );
        },
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final News news;
  final VoidCallback onTap;
  const _NewsCard({required this.news, required this.onTap});

  Widget _placeholder() => AspectRatio(
    aspectRatio: 16 / 9,
    child: Container(
      color: AppTheme.accentSoft,
      child: const Center(
        child: Icon(Icons.photo_outlined,
            size: 36, color: AppTheme.primaryNavy),
      ),
    ),
  );

  Widget _buildImageWidget() {
    final img = news.mainImage.isNotEmpty
        ? news.mainImage
        : (news.imageUrls.isNotEmpty ? news.imageUrls.first : '');

    if (img.isEmpty) return _placeholder();

    if (img.startsWith('http')) {
      return Image.network(
        img,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        cacheWidth: 800,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return _placeholder();
        },
      );
    }
    try {
      return Image.memory(
        base64Decode(img),
        fit: BoxFit.fitWidth,
        width: double.infinity,
        cacheWidth: 800,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  AppTone _categoryTone(String category) {
    switch (category) {
      case 'Спорт':
        return AppTone.warning;
      case 'Учёба':
        return AppTone.success;
      case 'Мероприятия':
        return AppTone.accent;
      case 'Награждения':
        return AppTone.danger;
      default:
        return AppTone.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = appMutedColor(context);

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (news.hasImage)
            ClipRRect(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  _buildImageWidget(),
                  if (news.imageUrls.length > 1)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.collections,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('${news.imageUrls.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (news.category.isNotEmpty)
                      AppBadge(news.category,
                          tone: _categoryTone(news.category)),
                    if (news.category.isNotEmpty && news.date.isNotEmpty)
                      const SizedBox(width: 8),
                    if (news.date.isNotEmpty)
                      Text(news.date,
                          style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(news.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (news.shortDescription.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(news.shortDescription,
                      style: TextStyle(fontSize: 13, color: muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}