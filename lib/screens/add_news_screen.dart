import '../utils/error_text.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import '../theme/app_theme.dart';
import '../models/news_model.dart';
import '../models/department_model.dart';
import '../services/news_service.dart';
import '../services/push_service.dart';

class AddNewsScreen extends StatefulWidget {
  final News? news;
  const AddNewsScreen({super.key, this.news});
  bool get isEditing => news != null;

  @override
  State<AddNewsScreen> createState() => _AddNewsScreenState();
}

class _AddNewsScreenState extends State<AddNewsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _shortDescController = TextEditingController();
  final _bodyController = TextEditingController();
  final _sourceNameController = TextEditingController();
  final _sourceUrlController = TextEditingController();

  final NewsService _newsService = NewsService();
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;
  List<String> _imageUrls = [];

  String _scope = 'university';
  String _category = 'Новости';
  String? _selectedDeptId;

  // Красивое описание разделов с иконками
  final List<Map<String, dynamic>> _scopes = [
    {'value': 'university', 'label': 'СВФУ', 'icon': Icons.account_balance, 'color': Colors.blue},
    {'value': 'institute', 'label': 'Мой институт', 'icon': Icons.school, 'color': Colors.orange},
    {'value': 'profkom', 'label': 'Профсоюз', 'icon': Icons.groups, 'color': Colors.purple},
  ];

  static const Map<String, List<String>> _categoriesMap = {
    'university': ['Новости', 'Спорт', 'Культура', 'Конференции', 'Мероприятия'],
    'institute': ['Новости', 'Объявления', 'События', 'Мероприятия'],
    'profkom': ['Новости', 'Мероприятия', 'Награждения'],
  };

  @override
  void initState() {
    super.initState();
    if (widget.news != null) {
      final news = widget.news!;
      _titleController.text = news.title;
      _shortDescController.text = news.shortDescription;
      _bodyController.text = news.body;
      _scope = news.scope;
      _sourceNameController.text = news.sourceName;
      _sourceUrlController.text = news.sourceUrl;
      _imageUrls = List.from(news.imageUrls);
      _selectedDeptId = news.departmentId.isNotEmpty ? news.departmentId : null;

      // Умная установка категории (если старая категория не входит в список нового раздела, ставим первую)
      final availableCats = _categoriesMap[_scope] ?? ['Новости'];
      if (availableCats.contains(news.category)) {
        _category = news.category;
      } else {
        _category = availableCats.first;
      }
    } else {
      _category = _categoriesMap[_scope]!.first;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _shortDescController.dispose();
    _bodyController.dispose();
    _sourceNameController.dispose();
    _sourceUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImages() async {
    try {
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
      if (images.isEmpty) return;
      setState(() => _isLoading = true);

      for (var image in images) {
        if (_imageUrls.length >= 10) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В новость можно добавить не больше 10 фото')));
          break;
        }
        final bytes = await image.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Фото «${image.name}» больше 5 МБ и пропущено')));
          continue;
        }
        final ext = image.name.contains('.') ? image.name.split('.').last.toLowerCase() : 'jpg';
        final safeExt = const ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_imageUrls.length}.$safeExt';

        await _supabase.storage.from('news_images').uploadBinary(
          fileName, Uint8List.fromList(bytes),
          fileOptions: FileOptions(cacheControl: '3600', upsert: false, contentType: safeExt == 'jpg' ? 'image/jpeg' : 'image/$safeExt'),
        );
        final publicUrl = _supabase.storage.from('news_images').getPublicUrl(fileName);
        setState(() => _imageUrls.add(publicUrl));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Не удалось загрузить фото')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNews() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final sourceUrl = _sourceUrlController.text.trim();
    if (sourceUrl.isNotEmpty && !sourceUrl.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ссылка на источник должна начинаться с https://')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userName = userDoc.data()?['name'] ?? (widget.news?.authorName ?? 'Администратор');

      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

      final news = News(
        id: widget.news?.id ?? '',
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        shortDescription: _shortDescController.text.trim(),
        date: widget.news?.date ?? dateStr,
        scope: _scope,
        category: _category,
        authorName: userName,
        authorId: widget.news?.authorId ?? user.uid,
        departmentId: _scope == 'institute' ? (_selectedDeptId ?? '') : '',
        imageUrls: _imageUrls,
        mainImage: _imageUrls.isNotEmpty ? _imageUrls.first : '',
        imageBase64: '',
        createdAt: widget.news?.createdAt ?? DateTime.now(),
        sourceName: _sourceNameController.text.trim(),
        sourceUrl: _sourceUrlController.text.trim(),
      );

      if (widget.isEditing) {
        await _newsService.updateNews(news);
      } else {
        final newsId = await _newsService.addNews(news);
        if (_scope == 'university' || _scope == 'profkom') {
          await PushService.sendNewsPush(
            newsId: newsId,
            title: news.title,
            message: news.shortDescription.isNotEmpty ? news.shortDescription : 'Нажмите, чтобы прочитать',
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteNews() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить новость?'),
        content: Text('Новость "${widget.news?.title}" будет удалена навсегда.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _newsService.deleteNews(widget.news!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentCategories = _categoriesMap[_scope] ?? ['Новости'];
    final currentScope = _scopes.firstWhere((s) => s['value'] == _scope);
    final Color scopeColor = currentScope['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Редактировать новость' : 'Добавить новость'),
        actions: [
          if (widget.isEditing)
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _isLoading ? null : _deleteNews),
        ],
      ),
      backgroundColor: AppTheme.backgroundGray,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              //  Красивый выбор раздела (в виде карточек)
              const Text('Где публикуем?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _scopes.map((s) {
                  final isSelected = _scope == s['value'];
                  final color = s['color'] as Color;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(s['icon'] as IconData, size: 16, color: isSelected ? Colors.white : color),
                        const SizedBox(width: 6),
                        Text(s['label'] as String),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: color,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold),
                    onSelected: _isLoading ? null : (selected) {
                      if (selected) {
                        setState(() {
                          _scope = s['value'] as String;
                          _category = _categoriesMap[_scope]!.first;
                          if (_scope != 'institute') _selectedDeptId = null;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              //  Выбор категории
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Категория *',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_offer, color: scopeColor),
                ),
                value: _category,
                items: currentCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: _isLoading ? null : (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 16),

              //  Выбор института
              if (_scope == 'institute')
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('departments').orderBy('shortName').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const LinearProgressIndicator();
                    final depts = snapshot.data!.docs.map((d) => Department.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Какое подразделение? *',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school, color: scopeColor),
                        ),
                        value: _selectedDeptId,
                        items: depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.shortName))).toList(),
                        onChanged: _isLoading ? null : (v) => setState(() => _selectedDeptId = v),
                        validator: (v) => v == null ? 'Выберите подразделение' : null,
                      ),
                    );
                  },
                ),

              // Заголовок и текст
              TextFormField(
                controller: _titleController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: 'Заголовок *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Введите заголовок' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shortDescController,
                enabled: !_isLoading,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Краткое описание *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Введите описание' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                enabled: !_isLoading,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Полный текст *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Введите текст' : null,
              ),

              const SizedBox(height: 24),

              // Блок фото
              Row(
                children: [
                  const Icon(Icons.photo_library, size: 18),
                  const SizedBox(width: 8),
                  const Text('Фотографии', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_imageUrls.isNotEmpty)
                    Text('${_imageUrls.length}/10', style: const TextStyle(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _isLoading ? null : _pickAndUploadImages,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _imageUrls.isEmpty ? Colors.grey.shade400 : Colors.transparent, style: _imageUrls.isEmpty ? BorderStyle.solid : BorderStyle.none),
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 30, color: scopeColor),
                      const SizedBox(height: 4),
                      const Text('Добавить фото', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              if (_imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: _imageUrls.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(_imageUrls[index], width: double.infinity, height: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                          ),
                          Positioned(
                            top: 4, right: 4,
                            child: GestureDetector(
                              onTap: () => setState(() => _imageUrls.removeAt(index)),
                              child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)),
                            ),
                          ),
                          if (index == 0)
                            Positioned(
                              bottom: 4, left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                                child: const Text('Главная', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),

              // Источник
              ExpansionTile(
                title: const Text('Источник (необязательно)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  const SizedBox(height: 10),
                  TextFormField(controller: _sourceNameController, enabled: !_isLoading, decoration: const InputDecoration(labelText: 'Название источника', hintText: 'Например: Сайт СВФУ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.info_outline))),
                  const SizedBox(height: 12),
                  TextFormField(controller: _sourceUrlController, enabled: !_isLoading, decoration: const InputDecoration(labelText: 'Ссылка на источник (URL)', hintText: 'https://...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link)), keyboardType: TextInputType.url),
                ],
              ),

              const SizedBox(height: 24),

              // Кнопка сохранения
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveNews,
                  icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(widget.isEditing ? Icons.save : Icons.send),
                  label: Text(_isLoading ? 'Сохранение...' : (widget.isEditing ? 'Сохранить изменения' : 'Опубликовать')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scopeColor, // Кнопка красится в цвет выбранного раздела
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}