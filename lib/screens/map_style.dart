// lib/screens/map_style.dart
// Палитра раздела «Карта»: тёмные стены, светлые комнаты, синий маршрут, красная метка.

import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class MapStyle {
  static const ink = Color(0xFF1B2A4A); // стены, основной текст
  static const slate = Color(0xFF3B4A63); // вторичный текст
  static const mute = Color(0xFF7C8AA0); // подписи
  static const canvas = Color(0xFFE6EBF1); // подложка карты
  static const lake = Color(0xFFBDD7F7); // рамки кнопок
  static const signal = Color(0xFF2F6BDB); // маршрут, активный этаж
  static const selected = Color(0xFFBCD3F5); // выбранный кабинет
  static const pin = Color(0xFFE5484D); // метка назначения
  static const sun = Color(0xFFFFD84D);

  /// Цифры одной ширины: номера кабинетов и время не «прыгают».
  static const tabular = [FontFeature.tabularFigures()];
}
