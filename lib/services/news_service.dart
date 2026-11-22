import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/news_model.dart';

class NewsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<News>> getNews({int limit = 20}) {
    return _db
        .collection('news')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => News.fromMap(d.data(), d.id)).toList());
  }

  Future<String> addNews(News news) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Пользователь не авторизован');
    final ref = await _db.collection('news').add(news.toMap());
    return ref.id;
  }

  Future<void> updateNews(News news) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Пользователь не авторизован');
    await _db.collection('news').doc(news.id).update(news.toMap());
  }

  Future<void> deleteNews(String newsId) async {
    await _db.collection('news').doc(newsId).delete();
  }
}