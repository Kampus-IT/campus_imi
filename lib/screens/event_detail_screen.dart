import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/user_avatar.dart';
import 'event_participants_screen.dart';
import 'full_screen_image_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final EventService _eventService = EventService();
  late Event _event;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _isBusy = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isOrganizer => _uid != null && _uid == _event.organizerId;
  bool get _isParticipant => _uid != null && _event.participants.contains(_uid);

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _sub = FirebaseFirestore.instance
        .collection('events')
        .doc(widget.event.id)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (!snap.exists || data == null) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _event = Event.fromMap(snap.id, data));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _friendlyError(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'Действие недоступно. Возможно, мероприятие уже завершено или email не подтверждён.';
      }
      if (e.code == 'unavailable') return 'Нет подключения к интернету';
      return 'Не удалось выполнить действие. Попробуйте позже.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _toggleParticipation() async {
    if (_event.isFinished) {
      _snack('Мероприятие завершено. Запись закрыта.', error: true);
      return;
    }
    setState(() => _isBusy = true);
    try {
      if (_isParticipant) {
        await _eventService.leaveEvent(_event.id);
        _snack('Вы отписались от мероприятия');
      } else {
        await _eventService.joinEvent(_event.id);
        _snack('Вы записались. Баллы (+${_event.points}) начислятся после посещения');
      }
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  ImageProvider? _eventImage() {
    if (_event.imageUrl.startsWith('https://') || _event.imageUrl.startsWith('http://')) {
      return NetworkImage(_event.imageUrl);
    }
    if (_event.imageBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(_event.imageBase64));
      } catch (_) {}
    }
    return null;
  }

  void _openFullImage(ImageProvider imageProvider) {
    final List<String> images = [];
    if (_event.imageUrl.isNotEmpty) {
      images.add(_event.imageUrl);
    } else if (_event.imageBase64.isNotEmpty) {
      images.add(_event.imageBase64);
    }

    if (images.isEmpty) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullScreenImageScreen(images: images, initialIndex: 0),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: appMutedColor(context)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = _event.isFinished;
    final image = _eventImage();
    final muted = appMutedColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isOrganizer)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (v) {
                if (v == 'delete') _showDeleteEventDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                      SizedBox(width: 8),
                      Text('Удалить мероприятие', style: TextStyle(color: AppTheme.danger)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ БЛОК КАРТИНКИ (Адаптивный, как в новостях)
            if (image != null)
              GestureDetector(
                onTap: () => _openFullImage(image),
                child: _AutoAspectImage(
                  provider: image,
                  placeholder: Container(
                    height: 240,
                    color: AppTheme.lightBlue,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            AppBadge('+${_event.points} баллов', tone: AppTone.warning, icon: Icons.star),
                            if (isFinished) const AppBadge('Завершено', tone: AppTone.success),
                            if (_isParticipant && !isFinished)
                              const AppBadge('Вы записаны', tone: AppTone.accent, icon: Icons.check),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _event.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        _info(Icons.calendar_today_outlined, _event.date),
                        _info(Icons.access_time, _event.time),
                        _info(Icons.location_on_outlined, _event.location),
                        const Divider(height: 24),
                        Row(
                          children: [
                            UserAvatar(userId: _event.organizerId, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Организатор', style: TextStyle(fontSize: 12, color: muted)),
                                  Text(
                                    _event.organizer,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(Icons.group_outlined, size: 18, color: muted),
                            const SizedBox(width: 8),
                            Text('Записались: ${_event.participants.length}'),
                            if (_event.attended.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success),
                              const SizedBox(width: 6),
                              Text(
                                'Пришли: ${_event.attended.length}',
                                style: const TextStyle(color: AppTheme.success),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_event.description.isNotEmpty) ...[
                    const AppSectionLabel('О мероприятии'),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _event.description,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _event.participants.isEmpty
                          ? null
                          : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EventParticipantsScreen(event: _event)),
                      ),
                      icon: const Icon(Icons.people_outline),
                      label: Text(
                        _event.participants.isEmpty
                            ? 'Пока никто не записался'
                            : 'Участники (${_event.participants.length})',
                      ),
                    ),
                  ),
                  if (!_isOrganizer) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: (isFinished || _isBusy) ? null : _toggleParticipation,
                        style: FilledButton.styleFrom(
                          backgroundColor: _isParticipant && !isFinished ? AppTheme.danger : null,
                        ),
                        child: _isBusy
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : Text(
                          isFinished
                              ? 'Мероприятие завершено'
                              : (_isParticipant ? 'Отписаться' : 'Записаться'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteEventDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить мероприятие?'),
        content: const Text('Мероприятие и список записавшихся будут удалены. Это нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _eventService.deleteEvent(_event.id);
                if (mounted) Navigator.pop(context, true);
              } catch (e) {
                _snack(_friendlyError(e), error: true);
              }
            },
            child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

/// ✅ Класс, который автоматически подбирает пропорции картинки,
/// чтобы ничего не обрезалось (как в новостях).
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