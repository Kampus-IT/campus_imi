import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_ui.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _toggle(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);

    // 1. Сохраняем выбор (расписание перепланирует напоминания само).
    SettingsService.instance.setNotificationsEnabled(value);

    bool permissionGranted = true;
    try {
      if (!value) {
        // 2. Отключаем: убираем локальные напоминания и push-подписку.
        await NotificationService.cancelAll();
        OneSignal.User.pushSubscription.optOut();
      } else {
        // 3. Включаем: просим разрешение системы, затем подписываемся.
        permissionGranted = await OneSignal.Notifications.requestPermission(true);
        OneSignal.User.pushSubscription.optIn();
      }
    } catch (e) {
      debugPrint('📨 [PUSH] Ошибка OneSignal: $e');
    }

    final text = !value
        ? 'Уведомления отключены'
        : (permissionGranted
        ? 'Уведомления включены'
        : 'Разрешите уведомления в настройках телефона, иначе они не придут');
    messenger.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final enabled = SettingsService.instance.notificationsEnabled;

        return Scaffold(
          appBar: AppBar(title: const Text('Уведомления')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: enabled,
                  title: const Text('Все уведомления', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Напоминания о парах, новости, мероприятия'),
                  onChanged: (v) => _toggle(context, v),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: enabled ? appAccentSoftColor(context) : const Color(0x1FFF9800),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                      color: enabled ? appAccentColor(context) : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        enabled
                            ? 'Вы получаете напоминания о парах за 10 минут, а также новости и события.'
                            : 'Уведомления отключены: напоминаний о парах, новостей и событий не будет.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
