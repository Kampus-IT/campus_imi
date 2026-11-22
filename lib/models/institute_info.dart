import 'package:cloud_firestore/cloud_firestore.dart';

class InstituteInfo {
  final String id;
  final String name;
  final String shortName;
  final String type;
  final int order;
  final bool isActive;
  final String logoUrl;
  final String about;
  final String history;
  final List<String> directions;
  final Map<String, dynamic>? admission;
  final Map<String, dynamic>? contacts;

  InstituteInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    this.order = 0,
    this.isActive = true,
    this.logoUrl = '',
    this.about = '',
    this.history = '',
    this.directions = const [],
    this.admission,
    this.contacts,
  });

  factory InstituteInfo.fromMap(String id, Map<String, dynamic> data) {
    return InstituteInfo(
      id: id,
      name: data['name'] ?? '',
      shortName: data['shortName'] ?? '',
      type: data['type'] ?? 'institute',
      order: data['order'] ?? 0,
      isActive: data['isActive'] ?? true,
      logoUrl: data['logoUrl'] ?? '',
      about: data['about'] ?? '',
      history: data['history'] ?? '',
      directions: List<String>.from(data['directions'] ?? []),
      admission: data['admission'] as Map<String, dynamic>?,
      contacts: data['contacts'] as Map<String, dynamic>?,
    );
  }
}