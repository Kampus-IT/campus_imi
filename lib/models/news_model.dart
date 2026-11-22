import 'package:cloud_firestore/cloud_firestore.dart';

class News {
  final String id;
  final String title;
  final String body;
  final String shortDescription;
  final String authorName;
  final String authorId;
  final String category;
  final String scope;
  final String date;
  final List<String> imageUrls;
  final String mainImage;
  final String imageBase64;
  final String departmentId;
  final String sourceName;
  final String sourceUrl;
  final DateTime? createdAt;

  News({
    required this.id,
    required this.title,
    required this.body,
    this.shortDescription = '',
    this.authorName = '',
    this.authorId = '',
    this.category = 'Новости',
    this.scope = 'university',
    required this.date,
    this.imageUrls = const [],
    this.mainImage = '',
    this.imageBase64 = '',
    this.departmentId = '',
    this.sourceName = '',
    this.sourceUrl = '',
    this.createdAt,
  });

  bool get hasImage => imageUrls.isNotEmpty || mainImage.isNotEmpty || imageBase64.isNotEmpty;
  bool get hasSource => sourceName.isNotEmpty || sourceUrl.isNotEmpty;

  String get timeAgo {
    if (createdAt == null) return date;
    final now = DateTime.now();
    final diff = now.difference(createdAt!);
    if (diff.inDays > 0) return '${diff.inDays} дн. назад';
    if (diff.inHours > 0) return '${diff.inHours} ч. назад';
    if (diff.inMinutes > 0) return '${diff.inMinutes} мин. назад';
    return 'Только что';
  }

  factory News.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? parsedDate;
    final rawDate = map['createdAt'];

    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate);
    }


    List<String> urls = List<String>.from(map['imageUrls'] ?? []);
    String mainImg = map['mainImage'] ?? '';

    final oldImageUrl = map['imageUrl'] ?? '';
    if (mainImg.isEmpty && oldImageUrl.isNotEmpty) {
      mainImg = oldImageUrl;
    }
    if (urls.isEmpty && oldImageUrl.isNotEmpty) {
      urls = [oldImageUrl];
    }

    return News(
      id: docId,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      shortDescription: map['shortDescription'] ?? '',
      authorName: map['authorName'] ?? '',
      authorId: map['authorId'] ?? '',
      category: map['category'] ?? 'Новости',
      scope: map['scope'] ?? 'university',
      date: map['date'] ?? '',
      imageUrls: urls,
      mainImage: mainImg,
      imageBase64: map['imageBase64'] ?? '',
      departmentId: map['departmentId'] ?? '',
      sourceName: map['sourceName'] ?? '',
      sourceUrl: map['sourceUrl'] ?? '',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'shortDescription': shortDescription,
      'authorName': authorName,
      'authorId': authorId,
      'category': category,
      'scope': scope,
      'date': date,
      'imageUrls': imageUrls,
      'mainImage': mainImage,
      'imageUrl': mainImage,
      'imageBase64': imageBase64,
      'departmentId': departmentId,
      'sourceName': sourceName,
      'sourceUrl': sourceUrl,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}