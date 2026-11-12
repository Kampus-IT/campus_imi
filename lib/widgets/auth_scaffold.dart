import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Общий каркас экранов входа, регистрации и восстановления пароля:
/// тёмная шапка с логотипом и светлая «шторка» с формой.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBg = theme.appBarTheme.backgroundColor ?? AppTheme.primaryNavy;
    final headerFg = theme.appBarTheme.foregroundColor ?? Colors.white;

    return Scaffold(
      backgroundColor: headerBg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 20),
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, size: 18, color: headerFg),
                      tooltip: 'Назад',
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const SizedBox(width: 16),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.gold, width: 2),
                    ),
                    child: const Icon(Icons.school_outlined, color: AppTheme.gold, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: headerFg,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: headerFg.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
