import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pottery_tracker/services/feedback_service.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = _MockAuth();
    when(() => auth.currentUser).thenReturn(null);
  });

  FeedbackService buildService() => FeedbackService(
    firestore: firestore,
    auth: auth,
    packageInfoLoader: () async => PackageInfo(
      appName: 'Potter Journal',
      packageName: 'com.albertxu.potterytracker',
      version: '1.1.0',
      buildNumber: '5',
    ),
    deviceInfoLoader: () async => {
      'platform': 'ios',
      'osVersion': 'iOS 26.2.1',
      'deviceModel': 'iPhone15,2',
    },
  );

  test('writes a doc with all fields populated', () async {
    final service = buildService();
    await service.submit(
      category: FeedbackCategory.bug,
      message: 'hello',
      replyEmail: 'a@b.com',
    );

    final docs = await firestore.collection('feedback').get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.first.data();
    expect(data['uid'], isNull);
    expect(data['category'], 'bug');
    expect(data['message'], 'hello');
    expect(data['replyEmail'], 'a@b.com');
    expect(data['appVersion'], '1.1.0+5');
    expect(data['platform'], 'ios');
    expect(data['osVersion'], 'iOS 26.2.1');
    expect(data['deviceModel'], 'iPhone15,2');
    expect(data['locale'], isNotNull);
    expect(data['createdAt'], isNotNull);
  });

  test('uses authenticated uid when signed in', () async {
    final user = _MockUser();
    when(() => user.uid).thenReturn('uid-123');
    when(() => auth.currentUser).thenReturn(user);

    final service = buildService();
    await service.submit(
      category: FeedbackCategory.feature,
      message: 'pls add tags',
    );

    final docs = await firestore.collection('feedback').get();
    expect(docs.docs.first.data()['uid'], 'uid-123');
  });

  test('omits replyEmail when not provided', () async {
    final service = buildService();
    await service.submit(category: FeedbackCategory.praise, message: 'love it');

    final data = (await firestore.collection('feedback').get()).docs.first
        .data();
    expect(data['replyEmail'], isNull);
  });

  test('substitutes "unknown" when device-info loader throws', () async {
    final service = FeedbackService(
      firestore: firestore,
      auth: auth,
      packageInfoLoader: () async => PackageInfo(
        appName: 'Potter Journal',
        packageName: 'com.albertxu.potterytracker',
        version: '1.1.0',
        buildNumber: '5',
      ),
      deviceInfoLoader: () async => throw Exception('boom'),
    );
    await service.submit(category: FeedbackCategory.other, message: 'meh');

    final data = (await firestore.collection('feedback').get()).docs.first
        .data();
    expect(data['platform'], 'unknown');
    expect(data['osVersion'], 'unknown');
    expect(data['deviceModel'], 'unknown');
  });
}
