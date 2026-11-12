import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_ui.dart';
import '../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (mounted) setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
        // Не сообщаем, есть ли такой аккаунт: показываем тот же результат.
          if (mounted) setState(() => _emailSent = true);
          break;
        case 'invalid-email':
          _snack('Некорректный email');
          break;
        case 'too-many-requests':
          _snack('Слишком много попыток. Попробуйте позже');
          break;
        case 'network-request-failed':
          _snack('Нет подключения к интернету');
          break;
        default:
          _snack('Не удалось отправить письмо. Попробуйте позже');
      }
    } catch (_) {
      _snack('Не удалось отправить письмо. Попробуйте позже');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Восстановление пароля',
      subtitle: 'ИМИ СВФУ',
      child: _emailSent ? _buildSuccess(context) : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Забыли пароль?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Введите email, указанный при регистрации. Мы отправим ссылку для сброса пароля.',
            style: TextStyle(color: appMutedColor(context), height: 1.4),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isLoading ? null : _sendResetEmail(),
            decoration: const InputDecoration(
              labelText: 'Электронная почта',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.validateEmail,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _sendResetEmail,
              child: _isLoading
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Отправить ссылку'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(child: AppIconBox(Icons.mark_email_read_outlined, size: 72, tone: AppTone.success)),
        const SizedBox(height: 20),
        const Text(
          'Проверьте почту',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Если аккаунт с адресом $email существует, мы отправили на него ссылку для сброса пароля. '
              'Проверьте также папку «Спам».',
          textAlign: TextAlign.center,
          style: TextStyle(color: appMutedColor(context), height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Вернуться ко входу'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _emailSent = false),
          child: const Text('Указать другой адрес'),
        ),
      ],
    );
  }
}
