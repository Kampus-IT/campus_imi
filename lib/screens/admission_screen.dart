// lib/screens/admission_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class AdmissionScreen extends StatelessWidget {
  final String instituteId;
  final String instituteName;

  const AdmissionScreen({
    super.key,
    this.instituteId = 'ИМИ',
    this.instituteName = 'ИМИ',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ Строгая проверка: данные только для ИМИ
    final id = instituteId.trim().toUpperCase();
    final isImi = id == 'ИМИ' || id == 'IMI';

    if (!isImi) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Поступающим'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.construction, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Информация для $instituteName скоро появится',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ===== ДАННЫЕ ДЛЯ ИМИ =====
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Поступающим'),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Шапка
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ИМИ СВФУ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Твой путь к цифровому будущему! Поступи в ИМИ и стань лучшим программистом.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'ПОЧЕМУ МЫ?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),

          _AdvantageCard(
            icon: Icons.computer,
            title: 'Освой востребованные технологии',
            description: 'Мы первые в республике запустили программу по искусственному интеллекту. Изучаем Python, Java, C#, C++ и современные фреймворки.',
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _AdvantageCard(
            icon: Icons.psychology,
            title: 'Фундаментальные знания',
            description: 'Математический анализ, теория алгоритмов, дискретная математика — всё это формирует мышление настоящего инженера.',
            color: Colors.purple,
          ),
          const SizedBox(height: 12),
          _AdvantageCard(
            icon: Icons.phone_android,
            title: 'Специальность полного цикла',
            description: 'От веб-приложений до блокчейна. Ты сможешь создавать как пользовательские интерфейсы, так и сложные серверные решения.',
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _AdvantageCard(
            icon: Icons.monetization_on,
            title: '200+ бюджетных мест',
            description: 'У нас есть более 200 бюджетных мест по IT-направлениям. Сдавай ЕГЭ по профильной математике, информатике и физике.',
            color: Colors.orange,
          ),
        ],
      ),
    );
  }
}

class _AdvantageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _AdvantageCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: appMutedColor(context), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}