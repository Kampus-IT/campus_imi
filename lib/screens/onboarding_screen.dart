import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_ui.dart';
import 'privacy_policy_screen.dart';

/// Первый запуск. Обязательно только согласие с политикой конфиденциальности.
/// Разрешение на уведомления необязательное: приложение работает и без него.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const OnboardingScreen({super.key, this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _notificationsGranted = false;
  bool _privacyChecked = false;
  bool _loading = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissions();
  }

  Future<void> _checkCurrentPermissions() async {
    try {
      final notif = await Permission.notification.isGranted;
      if (!mounted) return;
      setState(() {
        _notificationsGranted = notif;
        _loading = false;
      });
    } on MissingPluginException catch (e) {
      debugPrint('⚠️ [ONBOARDING] permission_handler недоступен: $e');
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('⚠️ [ONBOARDING] Ошибка проверки разрешений: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestNotifications() async {
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notificationsGranted = status.isGranted);
      if (status.isGranted) {
        await NotificationService.initialize();
      } else {
        // Пользователь отказал: не обещаем напоминания, которых не будет.
        SettingsService.instance.setNotificationsEnabled(false);
      }
    } on MissingPluginException catch (e) {
      debugPrint('⚠️ [ONBOARDING] permission_handler недоступен: $e');
    } catch (e) {
      debugPrint('⚠️ [ONBOARDING] Ошибка запроса уведомлений: $e');
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await SettingsService.instance.setPrivacyAccepted(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    if (!mounted) return;

    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
          (route) => false,
    );
  }

  Future<void> _openPolicy() async {
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen(showAcceptButton: true)),
    );
    if (accepted == true && mounted) setState(() => _privacyChecked = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = appMutedColor(context);

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Center(child: AppIconBox(Icons.school_outlined, size: 80)),
              const SizedBox(height: 24),
              Text(
                'Добро пожаловать',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Осталось принять политику конфиденциальности. Уведомления можно включить сейчас или позже в настройках.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.4),
              ),
              const SizedBox(height: 28),
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AppIconBox(
                          Icons.notifications_outlined,
                          tone: _notificationsGranted ? AppTone.success : AppTone.accent,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Уведомления',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              Text('Напоминания о парах, новости, события',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _notificationsGranted ? null : _requestNotifications,
                      child: Text(_notificationsGranted ? 'Разрешено' : 'Разрешить'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                value: _privacyChecked,
                onChanged: (v) => setState(() => _privacyChecked = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Wrap(
                  children: [
                    const Text('Я согласен с '),
                    GestureDetector(
                      onTap: _openPolicy,
                      child: Text(
                        'политикой конфиденциальности',
                        style: TextStyle(
                          color: appAccentColor(context),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Text(' и обработкой персональных данных'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _privacyChecked && !_finishing ? _finish : null,
                  child: const Text('Продолжить'),
                ),
              ),
              if (!_privacyChecked)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Чтобы продолжить, примите политику конфиденциальности',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
