import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _maxPhotoBytes = 3 * 1024 * 1024; // 3 МБ

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSaving = false;
  Uint8List? _newPhotoBytes;
  late final String _initialName;
  late final String _initialPhone;

  // ✅ Состояние для подгруппы
  int? _selectedSubgroup;

  @override
  void initState() {
    super.initState();
    _initialName = (widget.userData['name'] ?? '').toString();
    _initialPhone = (widget.userData['phone'] ?? '').toString();
    _nameController.text = _initialName;
    _phoneController.text = _initialPhone;
    _selectedSubgroup = widget.userData['subgroup'] as int?; // Загружаем подгруппу
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _newPhotoBytes != null ||
          _nameController.text.trim() != _initialName.trim() ||
          _phoneController.text.trim() != _initialPhone.trim() ||
          _selectedSubgroup != (widget.userData['subgroup'] as int?); // Проверяем изменение подгруппы

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

  Future<void> _pickAvatar() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        _snack('Фото слишком большое. Выберите файл до 3 МБ', error: true);
        return;
      }
      if (mounted) setState(() => _newPhotoBytes = bytes);
    } catch (_) {
      _snack('Не удалось выбрать фото', error: true);
    }
  }

  String? _validatePhone(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length < 10) return 'Номер слишком короткий';
    if (digits.length > 15) return 'Слишком длинный номер';
    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('not signed in');

      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'subgroup': _selectedSubgroup, // ✅ Сохраняем подгруппу
      };

      if (_newPhotoBytes != null) {
        final fileName = 'avatar_${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
          fileName,
          _newPhotoBytes!,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false, contentType: 'image/jpeg'),
        );
        updates['photoUrl'] = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
        updates['photoBase64'] = '';
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(updates);

      if (mounted) {
        _snack('Профиль обновлён');
        Navigator.pop(context, true);
      }
    } catch (_) {
      _snack('Не удалось сохранить профиль. Проверьте подключение и попробуйте ещё раз.', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти без сохранения?'),
        content: const Text('Внесённые изменения будут потеряны.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    return discard == true;
  }

  ImageProvider? _currentPhoto() {
    if (_newPhotoBytes != null) return MemoryImage(_newPhotoBytes!);
    final url = (widget.userData['photoUrl'] ?? '').toString();
    if (url.startsWith('https://')) return NetworkImage(url);
    final b64 = (widget.userData['photoBase64'] ?? '').toString();
    if (b64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(b64));
      } catch (_) {}
    }
    return null;
  }

  Widget _readOnlyRow(IconData icon, String label, String value, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          AppIconBox(icon, size: 40, tone: AppTone.neutral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: appMutedColor(context))),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(hint, style: TextStyle(fontSize: 11, color: appMutedColor(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = _currentPhoto();
    final institute = (widget.userData['institute'] ?? 'Не указано').toString();
    final group = (widget.userData['group'] ?? 'Не указана').toString();
    final course = (widget.userData['course'] ?? 'Не указан').toString();

    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Редактировать профиль')),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: appAccentSoftColor(context),
                          image: photo != null ? DecorationImage(image: photo, fit: BoxFit.cover) : null,
                        ),
                        child: photo == null ? Icon(Icons.person, size: 50, color: appAccentColor(context)) : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Material(
                          color: appAccentColor(context),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _isSaving ? null : _pickAvatar,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const AppSectionLabel('Личные данные'),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'ФИО', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 3) return 'Введите ФИО';
                    if (t.length > 100) return 'Слишком длинное имя';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Телефон (необязательно)', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: _validatePhone,
                ),
                const AppSectionLabel('Учёба'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _readOnlyRow(Icons.school_outlined, 'Подразделение', institute, 'Для смены обратитесь в деканат'),
                      const Divider(height: 1, indent: 64),
                      _readOnlyRow(Icons.groups_outlined, 'Группа', group, 'Для смены обратитесь в деканат'),
                      const Divider(height: 1, indent: 64),
                      _readOnlyRow(Icons.layers_outlined, 'Курс', course, 'Определяется по номеру группы'),
                    ],
                  ),
                ),

                // ✅ БЛОК ВЫБОРА ПОДГРУППЫ
                const AppSectionLabel('Подгруппа'),
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Укажите вашу подгруппу для отображения правильного расписания',
                        style: TextStyle(fontSize: 13, color: appMutedColor(context)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Все'),
                              selected: _selectedSubgroup == null,
                              onSelected: (val) => setState(() => _selectedSubgroup = null),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('1 пг'),
                              selected: _selectedSubgroup == 1,
                              onSelected: (val) => setState(() => _selectedSubgroup = 1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('2 пг'),
                              selected: _selectedSubgroup == 2,
                              onSelected: (val) => setState(() => _selectedSubgroup = 2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSaving || !_isDirty ? null : _saveProfile,
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}