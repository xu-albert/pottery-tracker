import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum FeedbackCategory { bug, feature, other, praise }

extension FeedbackCategoryX on FeedbackCategory {
  String get value {
    switch (this) {
      case FeedbackCategory.bug:
        return 'bug';
      case FeedbackCategory.feature:
        return 'feature';
      case FeedbackCategory.other:
        return 'other';
      case FeedbackCategory.praise:
        return 'praise';
    }
  }
}

class FeedbackService {
  FeedbackService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<Map<String, String>> Function()? deviceInfoLoader,
  }) : _firestore = firestore,
       _auth = auth,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _deviceInfoLoader = deviceInfoLoader ?? _defaultDeviceInfo;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<Map<String, String>> Function() _deviceInfoLoader;

  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    String? replyEmail,
  }) async {
    PackageInfo? pkg;
    Map<String, String>? device;
    try {
      pkg = await _packageInfoLoader();
    } catch (_) {}
    try {
      device = await _deviceInfoLoader();
    } catch (_) {}

    final appVersion = pkg != null
        ? '${pkg.version}+${pkg.buildNumber}'
        : 'unknown';

    await _firestore.collection('feedback').add({
      'uid': _auth.currentUser?.uid,
      'category': category.value,
      'message': message,
      'replyEmail': replyEmail,
      'appVersion': appVersion,
      'platform': device?['platform'] ?? 'unknown',
      'osVersion': device?['osVersion'] ?? 'unknown',
      'deviceModel': device?['deviceModel'] ?? 'unknown',
      'locale': PlatformDispatcher.instance.locale.toString(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, String>> _defaultDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await plugin.iosInfo;
      return {
        'platform': 'ios',
        'osVersion': '${ios.systemName} ${ios.systemVersion}',
        'deviceModel': ios.utsname.machine,
      };
    } else if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return {
        'platform': 'android',
        'osVersion': 'Android ${android.version.release}',
        'deviceModel': android.model,
      };
    }
    return {
      'platform': 'unknown',
      'osVersion': 'unknown',
      'deviceModel': 'unknown',
    };
  }
}
