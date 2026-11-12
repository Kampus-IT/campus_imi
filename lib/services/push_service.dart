import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class PushService {
  static const String _serverUrl = 'https://campus-push-api.onrender.com';

  static Future<void> sendNewsPush({
    required String newsId,
    required String title,
    required String message,
  }) {
    return _send(
      title: '📰 $title',
      message: message,
      type: 'news',
      targetId: newsId,
    );
  }

  static Future<void> sendEventPush({
    required String eventId,
    required String title,
    required String date,
    required String time,
    required String location,
    required int points,
  }) {
    final lines = <String>[
      title,
      '$date · $time',
      if (location.isNotEmpty) location,
      '+$points баллов',
    ];
    return _send(
      title: '🎉 Новое мероприятие',
      message: lines.join('\n'),
      type: 'event',
      targetId: eventId,
    );
  }

  // ✅ МЕТОД ДЛЯ РАСПИСАНИЯ
  static Future<void> sendSchedulePush({
    required String title,
    required String message,
  }) {
    return _send(
      title: '📅 $title',
      message: message,
      type: 'schedule',
      targetId: '', // Расписанию ID не нужен
    );
  }

  static Future<void> _send({
    required String title,
    required String message,
    required String type,
    required String targetId,
  }) async {
    if (!SettingsService.instance.notificationsEnabled) {
      debugPrint('📨 [PUSH] Уведомления отключены, отправка пропущена');
      return;
    }

    // ✅ ОТЛАДКА: Проверяем, что функция вообще вызвалась
    debugPrint('🚀 [PUSH] Пытаемся отправить пуш на сервер $_serverUrl...');

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http
          .post(
        Uri.parse('$_serverUrl/send-push'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'message': message,
          'type': type,
          'targetId': targetId,
        }),
      )
      // ✅ Таймаут увеличен до 50 секунд, чтобы бесплатный сервер Render успел проснуться
          .timeout(const Duration(seconds: 50));

      if (response.statusCode == 200) {
        debugPrint('✅ [PUSH] Успешно отправлен! Ответ сервера: ${response.body}');
      } else {
        debugPrint('❌ [PUSH] Ошибка сервера ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ [PUSH] Ошибка сети (Сервер спит?): $e');
    }
  }
}