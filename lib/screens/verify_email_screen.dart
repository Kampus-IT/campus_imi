import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/auth_scaffold.dart';

/// Экран, пока email не подтверждён. Без подтверждения в приложение не пускаем:
/// правила базы тоже требуют подтверждённый email для записи данных.
class VerifyEmailScreen extends StatefulWidget {
  /// Вызывается, когда подтверждение обнаружено.
  final VoidCallback onVerified;
  const VerifyEmailScreen({super.key, required this.onVerified});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _checking = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Тихо проверяем подтверждение каждые 5 секунд.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pollTimer?.cancel();
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

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    if (!silent && mounted) setState(() => _checking = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        // Обновляем токен: правила базы смотрят на email_verified в нём.
        await user.getIdToken(true);
        _pollTimer?.cancel();
        widget.onVerified();
        return;
      }
      if (!silent) _snack('Email ещё не подтверждён. Откройте ссылку из письма.');
    } catch (_) {
      if (!silent) _snack('Не удалось проверить. Проверьте подключение.', error: true);
    } finally {
      if (!silent && mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _snack('Письмо отправлено');
      setState(() => _cooldown = 60);
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _cooldown--);
        if (_cooldown <= 0) t.cancel();
      });
    } on FirebaseAuthException catch (e) {
      _snack(
        e.code == 'too-many-requests'
            ? 'Слишком часто. Подождите немного и повторите.'
            : 'Не удалось отправить письмо. Попробуйте позже.',
        error: true,
      );
    } catch (_) {
      _snack('Не удалось отправить письмо. Попробуйте позже.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return AuthScaffold(
      title: 'Подтвердите email',
      subtitle: 'Остался один шаг',
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(child: AppIconBox(Icons.mark_email_unread_outlined, size: 72)),
          const SizedBox(height: 20),
          Text(
            'Мы отправили письмо на',
            textAlign: TextAlign.center,
            style: TextStyle(color: appMutedColor(context)),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            'Откройте письмо и перейдите по ссылке, затем вернитесь сюда. '
                'Если письма нет, проверьте папку «Спам».',
            textAlign: TextAlign.center,
            style: TextStyle(color: appMutedColor(context), height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _checking ? null : () => _check(),
              child: _checking
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Я подтвердил(а) email'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _cooldown > 0 ? null : _resend,
              child: Text(
                _cooldown > 0 ? 'Отправить снова через $_cooldown с' : 'Отправить письмо снова',
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Выйти и войти в другой аккаунт'),
          ),
        ],
      ),
    );
  }
}
