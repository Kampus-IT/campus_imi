import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class FullScreenImageScreen extends StatefulWidget {
  /// Список картинок. Может быть либо http(s)-URL, либо base64-строкой.
  /// Каждая картинка проверяется отдельно — так проще, если в одной
  /// новости смешаны http и base64.
  final List<String> images;
  final int initialIndex;

  const FullScreenImageScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  }) : assert(images.length > 0, 'Нужна хотя бы одна картинка');

  /// Удобный конструктор для одной картинки (обратная совместимость).
  factory FullScreenImageScreen.single({
    Key? key,
    required String imageUrl,
    bool isBase64 = false,
  }) {
    return FullScreenImageScreen(key: key, images: [imageUrl]);
  }

  @override
  State<FullScreenImageScreen> createState() => _FullScreenImageScreenState();
}

class _FullScreenImageScreenState extends State<FullScreenImageScreen> {
  late final PageController _pageController;
  late int _index;

  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// http(s) → NetworkImage; иначе base64 → MemoryImage.
  ImageProvider? _provider(String src) {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return NetworkImage(src);
    }
    try {
      final bytes = base64Decode(src);
      return MemoryImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {},
      onVerticalDragUpdate: (d) => setState(() => _dragOffset += d.delta.dy),
      onVerticalDragEnd: (_) {
        if (_dragOffset.abs() > 120) {
          Navigator.of(context).maybePop();
        } else {
          setState(() => _dragOffset = 0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        body: Stack(
          children: [
            // Картинки
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final provider = _provider(widget.images[i]);
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: provider == null
                        ? const Icon(Icons.broken_image,
                        color: Colors.white54, size: 64)
                        : Image(
                      image: provider,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      width: double.infinity,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const CircularProgressIndicator(
                            color: Colors.white);
                      },
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 64),
                    ),
                  ),
                );
              },
            ),

            // Закрыть
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),

            // Счётчик 1 / N
            if (widget.images.length > 1)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.images.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}