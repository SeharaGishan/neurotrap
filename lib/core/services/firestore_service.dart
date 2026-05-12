import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Create user document on sign up ───────────────────────────────────────
  Future<void> createUser({
    required String uid,
    required String email,
    required String username,
  }) async {
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'username': username,
      'createdAt': FieldValue.serverTimestamp(),
      'emailVerified': false,
    });
  }

  // ── Get user document ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return doc.data();
    return null;
  }

  // ── Update email verified status ───────────────────────────────────────────
  Future<void> markEmailVerified(String uid) async {
    await _db.collection('users').doc(uid).update({
      'emailVerified': true,
    });
  }

  // ── Update user profile ────────────────────────────────────────────────────
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }
}