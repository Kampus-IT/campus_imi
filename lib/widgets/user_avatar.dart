import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  final String? userId;
  final Map<String, dynamic>? customUserData;
  final double size;
  final IconData icon;
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    this.userId,
    this.customUserData,
    required this.size,
    this.icon = Icons.person,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Если передали готовые данные (из списка)
    if (customUserData != null) {
      return _buildAvatar(context, customUserData!);
    }

    // Если передан ID — подписываемся на Firebase
    if (userId != null && userId!.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            return _buildAvatar(context, data);
          }
          return _buildPlaceholder(context);
        },
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildAvatar(BuildContext context, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    ImageProvider? imageProvider;

    // ✅ 1. Ищем ссылку на картинку (проверяем все возможные варианты имен)
    final photoUrl = data['photoUrl'] ?? data['avatarUrl'] ?? data['imageUrl'] ?? '';

    if (photoUrl is String && photoUrl.startsWith('http')) {
      imageProvider = NetworkImage(photoUrl);
    } else {
      // ✅ 2. Если ссылки нет, ищем Base64 (тоже во всех полях)
      final base64String = data['photoBase64'] ?? data['imageBase64'] ?? data['avatarBase64'] ?? '';

      if (base64String is String && base64String.isNotEmpty) {
        try {
          imageProvider = MemoryImage(base64Decode(base64String));
        } catch (_) {}
      }
    }

    // ✅ 3. Если картинки нет, берем имя и рисуем инициал
    if (imageProvider == null) {
      final name = data['name'] ?? data['fullName'] ?? '';
      final initial = name.isNotEmpty ? name[0].toUpperCase() : null;

      final bgColor = backgroundColor ?? theme.colorScheme.primary.withValues(alpha: 0.1);
      final textColor = backgroundColor != null ? Colors.white : theme.colorScheme.primary;

      if (initial != null) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        );
      }
      // Если даже имени нет — показываем иконку
      return _buildPlaceholder(context);
    }

    // Если картинка нашлась - показываем её
    final bgColor = backgroundColor ?? theme.colorScheme.primary.withValues(alpha: 0.1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary.withValues(alpha: 0.1);
    final iconColor = backgroundColor != null ? Colors.white : theme.colorScheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
      child: Icon(icon, size: size * 0.6, color: iconColor),
    );
  }
}