import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/department_model.dart';
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

  String? _selectedDeptId;
  String? _selectedGroup;
  int _calculatedCourse = 1;

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
    if (_selectedDeptId == null || _selectedGroup == null) {
      _snack('Выберите подразделение и группу');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final name = _nameController.text.trim();
    User? createdUser;

    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user == null) throw Exception('user is null');
      createdUser = user;

      await user.updateDisplayName(name);

      // ✅ КРИТИЧНО: принудительно обновляем токен, чтобы Firestore видел авторизацию
      await user.getIdToken(true);

      // ✅ Небольшая пауза для синхронизации
      await Future.delayed(const Duration(milliseconds: 500));

      final deptDoc =
      await FirebaseFirestore.instance.collection('departments').doc(_selectedDeptId).get();
      final deptName = (deptDoc.data()?['name'] ?? '').toString();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'group': _selectedGroup,
        'departmentId': _selectedDeptId,
        'institute': deptName,
        'course': '$_calculatedCourse курс',
        'phone': '',
        'role': 'student',
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'photoBase64': '',
      });

      await user.sendEmailVerification();

      // Дальше AuthWrapper сам покажет экран подтверждения email.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      await _rollback(createdUser);
      _snack(_registerError(e));
    } catch (e) {
      // Если ошибка не связана с Auth (например, Firestore), показываем её
      await _rollback(createdUser);
      if (mounted) _snack('Ошибка: $e');
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
    final theme = Theme.of(context);
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

            // 1. Подразделение
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Не удалось загрузить подразделения. Проверьте подключение.',
                    style: TextStyle(color: AppTheme.danger),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final depts = snapshot.data!.docs
                    .map((d) => Department.fromMap(d.id, d.data() as Map<String, dynamic>))
                    .toList();
                final isValid = depts.any((d) => d.id == _selectedDeptId);

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Подразделение',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  value: isValid ? _selectedDeptId : null,
                  isExpanded: true,
                  dropdownColor: theme.cardColor,
                  items: depts
                      .map((d) => DropdownMenuItem(value: d.id, child: Text(d.shortName)))
                      .toList(),
                  onChanged: _isLoading
                      ? null
                      : (val) => setState(() {
                    _selectedDeptId = val;
                    _selectedGroup = null;
                  }),
                  validator: (v) => v == null ? 'Выберите подразделение' : null,
                );
              },
            ),
            const SizedBox(height: 16),

            // 2. Группа выбранного подразделения
            if (_selectedDeptId != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .where('departmentId', isEqualTo: _selectedDeptId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'Не удалось загрузить группы. Проверьте подключение.',
                      style: TextStyle(color: AppTheme.danger),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final groups = (snapshot.data?.docs
                      .map((d) => (d.data() as Map<String, dynamic>)['name']?.toString() ?? '')
                      .where((n) => n.isNotEmpty)
                      .toList() ??
                      [])
                    ..sort();
                  final isValidGroup = groups.contains(_selectedGroup);

                  if (groups.isEmpty) {
                    return Text(
                      'Для этого подразделения пока нет групп. Обратитесь к администратору.',
                      style: TextStyle(color: appMutedColor(context)),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Группа',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    value: isValidGroup ? _selectedGroup : null,
                    isExpanded: true,
                    dropdownColor: theme.cardColor,
                    items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: _isLoading
                        ? null
                        : (val) => setState(() {
                      _selectedGroup = val;
                      if (val != null) _calculatedCourse = _calculateCourse(val);
                    }),
                    validator: (v) => v == null ? 'Выберите группу' : null,
                  );
                },
              ),
            if (_selectedDeptId != null) const SizedBox(height: 16),

            if (_selectedGroup != null) ...[
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const AppIconBox(Icons.layers_outlined, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Курс', style: TextStyle(fontSize: 12, color: appMutedColor(context))),
                          Text(
                            '$_calculatedCourse курс · определён по номеру группы',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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