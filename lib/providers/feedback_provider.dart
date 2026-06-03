import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/feedback_service.dart';

final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  return FeedbackService(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});
