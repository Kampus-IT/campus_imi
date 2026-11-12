import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/user_avatar.dart';
import 'event_participants_screen.dart';

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
    // Следим за мероприятием: число записавшихся и статус всегда актуальны.
    _sub = FirebaseFirestore.instance
        .collection('events')
        .doc(widget.event.id)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (!snap.exists || data == null) {
        // Мероприятие удалили, пока экран был открыт.
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
    if (_event.imageUrl.startsWith('https://')) return NetworkImage(_event.imageUrl);
    if (_event.imageBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(_event.imageBase64));
      } catch (_) {}
    }
    return null;
  }

  void _openFullImage(ImageProvider imageProvider) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(child: Image(image: imageProvider)),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(ctx),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
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
            if (image != null)
              GestureDetector(
                onTap: () => _openFullImage(image),
                child: SizedBox(
                  height: 240,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Image(image: image, fit: BoxFit.cover),
                      ),
                      Container(color: Colors.black.withValues(alpha: 0.4)),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image(image: image, fit: BoxFit.contain),
                        ),
                      ),
                    ],
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
                        style: const TextStyle(fontSize: 14, height: 1.6),
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
