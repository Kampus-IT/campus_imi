// lib/screens/guest_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../services/settings_service.dart';
import 'institute_screen.dart';
import 'institute_list_screen.dart';
import 'admission_screen.dart';
import 'staff_screen.dart';
import 'profkom_screen.dart';
import 'indoor_map_screen.dart';

class GuestScreen extends StatelessWidget {
  final String instituteId;
  final String instituteName;

  const GuestScreen({
    super.key,
    this.instituteId = 'ИМИ',
    this.instituteName = 'ИМИ',
  });

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              tooltip: 'Назад',
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Гость: $instituteName'),
            actions: [
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? Colors.amber : Colors.white,
                ),
                tooltip: 'Сменить тему',
                onPressed: () {
                  SettingsService.instance.setTheme(
                    isDark ? ThemeMode.light : ThemeMode.dark,
                  );
                },
              ),
            ],
          ),
          backgroundColor: theme.scaffoldBackgroundColor,
          body: ListView(
            padding: const EdgeInsets.all(AppTheme.s16),
            children: [
              GestureDetector(
                onTap: () => _open(context, const InstituteListScreen()),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [AppTheme.accentSoftDark, AppTheme.darkCard]
                          : [AppTheme.primaryNavy, const Color(0xFF3D6FA3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.account_balance, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Сменить институт',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Все институты и факультеты Kampus-IT NEFU',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.s20),

              Container(
                padding: const EdgeInsets.all(AppTheme.s12),
                decoration: BoxDecoration(
                  color: appAccentSoftColor(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: appAccentColor(context), size: 22),
                    const SizedBox(width: AppTheme.s12),
                    Expanded(
                      child: Text(
                        'Расписание, зачётка и задания доступны после входа',
                        style: TextStyle(fontSize: 13, color: appAccentColor(context)),
                      ),
                    ),
                  ],
                ),
              ),
              const AppSectionLabel('Доступно гостям'),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    AppListRow(
                      icon: Icons.account_balance_outlined,
                      title: instituteName,
                      subtitle: 'История, направления, кафедры',
                      onTap: () => _open(context, InstituteScreen(instituteId: instituteId)),
                    ),
                    const Divider(height: 1, indent: 64),
                    AppListRow(
                      icon: Icons.school_outlined,
                      title: 'Поступающим',
                      subtitle: 'Бакалавриат и магистратура',
                      // ✅ Передаем ID и имя
                      onTap: () => _open(context, AdmissionScreen(
                        instituteId: instituteId,
                        instituteName: instituteName,
                      )),
                    ),
                    const Divider(height: 1, indent: 64),
                    AppListRow(
                      icon: Icons.people_outline,
                      title: 'Сотрудники института',
                      subtitle: 'Руководство и преподаватели',
                      onTap: () => _open(context, StaffScreen(instituteId: instituteId)),
                    ),
                    const Divider(height: 1, indent: 64),
                    AppListRow(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Профсоюз СВФУ',
                      subtitle: 'Студенческий профсоюз',
                      onTap: () => _open(context, const ProfkomScreen()),
                    ),
                    const Divider(height: 1, indent: 64),
                    AppListRow(
                      icon: Icons.map_outlined,
                      title: 'Карта корпуса',
                      subtitle: 'Навигация по этажам',
                      // ✅ Используем локальные методы
                      onTap: () => _open(context, IndoorMapScreen(
                        buildingId: _getBuildingIdForInstitute(instituteId),
                        buildingName: _getBuildingNameForInstitute(instituteId),
                      )),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.s16),

              AppCard(
                padding: const EdgeInsets.all(AppTheme.s16),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline, size: 28, color: appAccentColor(context)),
                    const SizedBox(height: 6),
                    const Text(
                      'Больше возможностей после входа',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Расписание, оценки, задания и события',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: appMutedColor(context)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Войти'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.s24),
              Center(
                child: Text(
                  '© Kampus-IT NEFU',
                  style: TextStyle(fontSize: 11, color: appMutedColor(context)),
                ),
              ),
              const SizedBox(height: AppTheme.s16),
            ],
          ),
        );
      },
    );
  }

  // Вспомогательные методы для определения корпуса по институту
  String _getBuildingIdForInstitute(String id) {
    if (id.contains('ИМИ') || id.contains('ИЕН') || id.contains('ФТИ')) return 'ammosov';
    if (id.contains('ГИ') || id.contains('ГРФ') || id.contains('ИТИ') || id.contains('АДФ')) return 'ktf';
    if (id.contains('ЮФ') || id.contains('ФЛФ') || id.contains('ИП') || id.contains('ФЭИ')) return 'guk';
    if (id.contains('ПИ')) return 'pi';
    if (id.contains('КИТ')) return 'kit';
    return 'ammosov'; // По умолчанию
  }

  String _getBuildingNameForInstitute(String id) {
    if (id.contains('ИМИ') || id.contains('ИЕН') || id.contains('ФТИ')) return 'КФЕН';
    if (id.contains('ГИ') || id.contains('ГРФ') || id.contains('ИТИ') || id.contains('АДФ')) return 'КТФ';
    if (id.contains('ЮФ') || id.contains('ФЛФ') || id.contains('ИП') || id.contains('ФЭИ')) return 'ГУК';
    if (id.contains('ПИ')) return 'Педагогический институт';
    if (id.contains('КИТ')) return 'КИТ';
    return 'Корпус';
  }
}