// lib/screens/institute_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/institute_info.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'admission_screen.dart';
import 'staff_screen.dart';

class InstituteScreen extends StatefulWidget {
  final String instituteId;

  const InstituteScreen({super.key, required this.instituteId});

  @override
  State<InstituteScreen> createState() => _InstituteScreenState();
}

class _InstituteScreenState extends State<InstituteScreen> {
  InstituteInfo? _info;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('departments')
          .doc(widget.instituteId)
          .get();
      if (doc.exists) {
        _info = InstituteInfo.fromMap(doc.id, doc.data()!);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Загрузка...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_info == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ошибка')),
        body: const Center(child: Text('Подразделение не найдено')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_info!.shortName),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Шапка
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.accentSoftDark : AppTheme.primaryNavy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: _info!.logoUrl.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(_info!.logoUrl, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.school, color: Colors.white, size: 50)),
                  )
                      : const Icon(Icons.school, color: Colors.white, size: 50),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_info!.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_info!.about.isNotEmpty ? _info!.about : 'Kampus-IT NEFU', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Кнопки
          _BigButton(
            title: 'ПОСТУПАЮЩИМ',
            subtitle: _info!.admission != null ? '${_info!.admission!['budget'] ?? '?'} бюджетных мест' : 'Информация скоро появится',
            icon: Icons.school_outlined,
            isEnabled: _info!.admission != null,
            // ✅ Передаем ID и имя
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdmissionScreen(
              instituteId: _info!.shortName,
              instituteName: _info!.shortName,
            ))),
          ),
          const SizedBox(height: 12),
          _BigButton(
            title: 'СОТРУДНИКИ',
            subtitle: 'Руководство и преподаватели',
            icon: Icons.people,
            isEnabled: true,
            // ✅ Передаем ID
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffScreen(instituteId: _info!.shortName))),
          ),
          const SizedBox(height: 20),

          // О подразделении
          if (_info!.history.isNotEmpty || _info!.directions.isNotEmpty) ...[
            const AppSectionLabel('О ПОДРАЗДЕЛЕНИИ'),
            if (_info!.history.isNotEmpty)
              _Section(
                title: 'История',
                icon: Icons.history_edu,
                children: [_Paragraph(_info!.history)],
              ),
            if (_info!.directions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Направления подготовки',
                icon: Icons.workspaces_outline,
                children: _info!.directions.map((d) => _DirectionItem(label: d)).toList(),
              ),
            ],
          ] else ...[
            // Заглушка, если данных нет
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  Icon(Icons.construction, size: 48, color: appMutedColor(context)),
                  const SizedBox(height: 16),
                  const Text('Информация скоро появится', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Мы уже работаем над заполнением этой страницы.', textAlign: TextAlign.center, style: TextStyle(color: appMutedColor(context))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              '© Kampus-IT NEFU',
              style: TextStyle(fontSize: 11, color: appMutedColor(context).withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ===== БОЛЬШАЯ КНОПКА =====
class _BigButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isEnabled;
  final VoidCallback onTap;

  const _BigButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isEnabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isEnabled ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: isEnabled ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.dividerColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isEnabled ? theme.colorScheme.primary : theme.disabledColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: isEnabled ? theme.textTheme.bodyLarge?.color : theme.disabledColor)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: appMutedColor(context))),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: isEnabled ? theme.colorScheme.primary : theme.disabledColor),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== СЕКЦИЯ =====
class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== ПАРАГРАФ =====
class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color, height: 1.6),
    );
  }
}

// ===== НАПРАВЛЕНИЕ =====
class _DirectionItem extends StatelessWidget {
  final String label;

  const _DirectionItem({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.dividerColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color))),
        ],
      ),
    );
  }
}