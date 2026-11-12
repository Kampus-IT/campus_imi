import 'package:firebase_core/firebase_core.dart';

/// Превращает ошибку в понятное сообщение для пользователя.
/// Технические подробности (коды, трассировки, пути) наружу не показываем.
String friendlyError(
    Object e, {
      String fallback = 'Не удалось выполнить действие. Попробуйте ещё раз.',
    }) {
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Недостаточно прав для этого действия';
      case 'unavailable':
      case 'network-request-failed':
        return 'Нет подключения к интернету';
      case 'not-found':
        return 'Данные не найдены';
      case 'unauthenticated':
        return 'Войдите в аккаунт и повторите';
      default:
        return fallback;
    }
  }
  if (e is FormatException) return 'Некорректные данные';

  // Свои исключения приложения написаны по-русски: их показываем как есть.
  final text = e.toString();
  if (e is Exception && text.startsWith('Exception: ')) {
    final message = text.substring('Exception: '.length).trim();
    if (message.isNotEmpty &&
        message.length <= 140 &&
        RegExp(r'[А-Яа-яЁё]').hasMatch(message)) {
      return message;
    }
  }
  return fallback;
}
