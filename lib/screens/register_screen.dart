import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_ui.dart';
import '../widgets/auth_scaffold.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _groupCodeController = TextEditingController(); // ✅ Контроллер для секретного кода

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  static const List<String> _allowedDomains = [
    's-vfu.ru', 'students.s-vfu.ru', 'yandex.ru', 'ya.ru', 'mail.ru', 'inbox.ru',
    'list.ru', 'bk.ru', 'internet.ru', 'gmail.com', 'googlemail.com', 'icloud.com',
    'me.com', 'mac.com',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _groupCodeController.dispose(); // ✅ Очищаем контроллер кода
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

  int _calculateCourse(String groupName) {
    final match = RegExp(r'(\d{2})$').firstMatch(groupName);
    if (match == null) return 1;
    final admissionYear = 2000 + int.parse(match.group(1)!);
    final now = DateTime.now();
    final academicYear = now.month >= 9 ? now.year : now.year - 1;
    final course = academicYear - admissionYear + 1;
    if (course < 1) return 1;
    if (course > 6) return 6;
    return course;
  }

  String? _validateEmail(String? value) {
    final base = Validators.validateEmail(value);
    if (base != null) return base;
    final domain = value!.trim().split('@').last.toLowerCase();
    if (!_allowedDomains.contains(domain)) return 'Этот домен не поддерживается';
    return null;
  }

  String _registerError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Этот email уже зарегистрирован. Попробуйте войти';
      case 'invalid-email':
        return 'Некорректный email';
      case 'weak-password':
        return 'Слишком простой пароль';
      case 'network-request-failed':
        return 'Нет подключения к интернету';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуйте позже';
      default:
        return 'Не удалось создать аккаунт. Попробуйте ещё раз';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final groupCode = _groupCodeController.text.trim().toUpperCase();
    if (groupCode.isEmpty) {
      _snack('Введите секретный код группы');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final name = _nameController.text.trim();
    User? createdUser;

    try {
      // 1. Проверяем существование группы по секретному коду в Firestore ДО создания Auth-аккаунта
      final groupQuery = await FirebaseFirestore.instance
          .collection('groups')
          .where('code', isEqualTo: groupCode)
          .limit(1)
          .get();

      if (groupQuery.docs.isEmpty) {
        throw Exception('Группа с таким кодом не найдена. Проверьте правильность кода у старосты.');
      }

      final groupDoc = groupQuery.docs.first;
      final groupData = groupDoc.data();
      final groupName = (groupData['name'] ?? '').toString();
      final deptId = (groupData['departmentId'] ?? '').toString();

      if (groupName.isEmpty) {
        throw Exception('Не удалось определить название группы по коду.');
      }

      // 2. Получаем название института/подразделения
      String deptName = '';
      if (deptId.isNotEmpty) {
        final deptDoc = await FirebaseFirestore.instance.collection('departments').doc(deptId).get();
        deptName = (deptDoc.data()?['name'] ?? '').toString();
      }

      final calculatedCourse = _calculateCourse(groupName);

      // 3. Создаем пользователя в Firebase Auth
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user == null) throw Exception('user is null');
      createdUser = user;

      await user.updateDisplayName(name);

      // ✅ Принудительно обновляем токен, чтобы Firestore видел авторизацию
      await user.getIdToken(true);
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Сохраняем профиль в Firestore с автоматической привязкой группы и института
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'group': groupName,
        'departmentId': deptId,
        'institute': deptName,
        'course': '$calculatedCourse курс',
        'phone': '',
        'role': 'student',
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'photoBase64': '',
      });

      await user.sendEmailVerification();

      // Возвращаемся на стартовый экран (AuthWrapper сам перенаправит на верификацию email)
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      await _rollback(createdUser);
      _snack(_registerError(e));
    } catch (e) {
      await _rollback(createdUser);
      if (mounted) _snack('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rollback(User? user) async {
    if (user == null) return;
    try {
      await user.delete();
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Регистрация',
      subtitle: 'Создайте аккаунт студента',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'ФИО',
                helperText: 'Фамилия Имя Отчество',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Введите ФИО';
                if (t.length < 3) return 'Слишком короткое имя';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ✅ Поле ввода секретного кода группы вместо выпадающих списков
            TextFormField(
              controller: _groupCodeController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Секретный код группы',
                helperText: 'Введите код, полученный от старосты',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Введите секретный код группы';
                if (t.length < 4) return 'Код слишком короткий';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Электронная почта',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Пароль',
                helperText: 'Не короче 8 символов, буквы и цифры',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: Validators.validateNewPassword,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_isLoading,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _isLoading ? null : _register(),
              decoration: InputDecoration(
                labelText: 'Повторите пароль',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirm ? 'Показать пароль' : 'Скрыть пароль',
                  icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) => v != _passwordController.text ? 'Пароли не совпадают' : null,
            ),
            const SizedBox(height: 24),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Text('Зарегистрироваться'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}