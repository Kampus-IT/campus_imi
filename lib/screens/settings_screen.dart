import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/settings_service.dart';
import '../widgets/app_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Слушаем изменения, чтобы экран перерисовывался при смене темы и языка.
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final langCode = SettingsService.instance.locale.languageCode;
        String t(String key) => AppStrings.t(key, langCode);
        final themeMode = SettingsService.instance.themeMode;

        const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
        final themeIndex = modes.indexOf(themeMode).clamp(0, 2);
        final languages = ['ru', 'en'];
        final langIndex = languages.indexOf(langCode).clamp(0, 1);

        return Scaffold(
          appBar: AppBar(title: Text(t('settings'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppSectionLabel(t('theme'), padding: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
              AppSegmented(
                labels: [t('theme_system'), t('theme_light'), t('theme_dark')],
                index: themeIndex,
                onChanged: (i) => SettingsService.instance.setTheme(modes[i]),
              ),
              AppSectionLabel(t('language')),
              AppSegmented(
                labels: const ['Русский', 'English'],
                index: langIndex,
                onChanged: (i) => SettingsService.instance.setLanguage(languages[i]),
              ),
            ],
          ),
        );
      },
    );
  }
}
