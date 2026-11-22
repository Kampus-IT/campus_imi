import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/news_model.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'add_news_screen.dart';
import 'full_screen_image_screen.dart';

class NewsDetailScreen extends StatefulWidget {
  final News news;
  const NewsDetailScreen({super.key, required this.news});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && doc.data()?['role'] == 'admin') {
      if (mounted) setState(() => _isAdmin = true);
    }
  }

  Color get _categoryColor {
    switch (widget.news.category) {
      case 'Trending':
        return Colors.red;
      case 'Спорт':
        return Colors.orange;
      case 'Учёба':
        return AppTheme.accentBlue;
      case 'События':
        return Colors.purple;
      case 'Культура':
        return Colors.teal;
      default:
        return appMutedColor(context);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// http(s) → NetworkImage; иначе base64 → MemoryImage.
  ImageProvider? _imageProvider(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    }
    try {
      return MemoryImage(base64Decode(url));
    } catch (_) {
      return null;
    }
  }

  /// Открыть полноэкранный просмотрщик (телеграм-стиль).
  void _openViewer(int index) {
    final urls = widget.news.imageUrls;
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            FullScreenImageScreen(images: urls, initialIndex: index),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Картинка «во всю ширину» с сохранением пропорций (как в Telegram).
  Widget _buildImageCarousel() {
    final urls = widget.news.imageUrls;
    if (urls.isEmpty) return const SizedBox.shrink();

    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openViewer(0),
        child: _AutoAspectImage(
          provider: _imageProvider(urls.first),
          placeholder: Container(
            height: 240,
            color: AppTheme.lightBlue,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    return SizedBox(
      height: 380,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: urls.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openViewer(i),
              child: _AutoAspectImage(
                provider: _imageProvider(urls[i]),
                placeholder: Container(color: AppTheme.lightBlue),
              ),
            ),
          ),
          // Счётчик 1 / N
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentPage + 1} / ${urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // Точки
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ✅ Разбиваем текст на абзацы для красивого чтения
    final paragraphs = widget.news.body
        .split('\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Новость'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Редактировать',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddNewsScreen(news: widget.news)),
                );
                if (result == true && mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.news.hasImage) _buildImageCarousel(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _categoryColor.withValues(alpha: 0.1),
                          borderRadius:
                          BorderRadius.circular(AppTheme.radiusPill),
                        ),
                        child: Text(
                          widget.news.category.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              color: _categoryColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time,
                          size: 14,
                          color: theme.textTheme.bodySmall?.color),
                      const SizedBox(width: 4),
                      Text(widget.news.timeAgo,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ✅ Крупный и жирный заголовок
                  Text(
                    widget.news.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ✅ Блок автора
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.1),
                        ),
                        child: Icon(Icons.person,
                            size: 24, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.news.authorName,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text(widget.news.date,
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Divider(color: theme.dividerColor, height: 1),
                  const SizedBox(height: 24),

                  // ✅ КРАСИВЫЙ ТЕКСТ: разбит на абзацы, с комфортным межстрочным интервалом
                  ...paragraphs.map((paragraph) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        paragraph,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 17,
                          height: 1.65,
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                        ),
                      ),
                    );
                  }),

                  // Источник
                  if (widget.news.hasSource)
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.source,
                                    size: 18,
                                    color: theme.textTheme.bodySmall?.color),
                                const SizedBox(width: 8),
                                Text(
                                  'Источник',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                      theme.textTheme.bodySmall?.color),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (widget.news.sourceName.isNotEmpty)
                              Text(
                                widget.news.sourceName,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontStyle: FontStyle.italic),
                              ),
                            if (widget.news.sourceUrl.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: GestureDetector(
                                  onTap: () async {
                                    final url = Uri.tryParse(
                                        widget.news.sourceUrl);
                                    if (url == null ||
                                        url.scheme != 'https') {
                                      return;
                                    }
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url,
                                          mode:
                                          LaunchMode.externalApplication);
                                    }
                                  },
                                  child: Text(
                                    widget.news.sourceUrl,
                                    style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        decoration:
                                        TextDecoration.underline,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Автоматически подбирает пропорции картинки, чтобы она не была обрезана
/// и не была слишком маленькой (как в Telegram: вертикальная — высокая,
/// горизонтальная — полосой).
class _AutoAspectImage extends StatefulWidget {
  final ImageProvider? provider;
  final Widget placeholder;
  const _AutoAspectImage({required this.provider, required this.placeholder});

  @override
  State<_AutoAspectImage> createState() => _AutoAspectImageState();
}

class _AutoAspectImageState extends State<_AutoAspectImage> {
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AutoAspectImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _aspectRatio = null;
      _resolve();
    }
  }

  void _resolve() {
    final p = widget.provider;
    if (p == null) return;
    final stream = p.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
          (info, _) {
        if (!mounted) {
          stream.removeListener(listener);
          return;
        }
        setState(() => _aspectRatio = info.image.width / info.image.height);
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    if (provider == null) return widget.placeholder;

    return AspectRatio(
      aspectRatio: _aspectRatio ?? (16 / 9),
      child: Image(
        image: provider,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => widget.placeholder,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return widget.placeholder;
        },
      ),
    );
  }
}