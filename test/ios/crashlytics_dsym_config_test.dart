import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedIosAppId = '1:22629038852:ios:21037012b59e03d00fae51';

  group('H1: iOS Crashlytics dSYM upload wiring', () {
    final postXcodebuild = File('ios/ci_scripts/ci_post_xcodebuild.sh');

    test('ci_post_xcodebuild.sh exists and is executable', () {
      expect(postXcodebuild.existsSync(), isTrue);
      final mode = postXcodebuild.statSync().mode;
      expect(mode & 0x49, isNonZero, reason: 'script must have execute bit');
    });

    test(
      'ci_post_xcodebuild.sh synchronously uploads archive dSYMs without --validate or backgrounding',
      () {
        final content = postXcodebuild.readAsStringSync();
        expect(content, contains('CI_XCODEBUILD_ACTION'));
        expect(content, contains('archive'));
        expect(content, contains('upload-symbols'));
        expect(content, contains('GoogleService-Info.plist'));
        expect(content, contains('-p ios'));
        expect(content, contains('dSYMs'));
        expect(content, isNot(contains('--validate')));
        expect(
          RegExp(r'upload-symbols.*&\s*$', multiLine: true).hasMatch(content),
          isFalse,
          reason: 'Xcode Cloud must run upload-symbols synchronously',
        );
      },
    );

    test(
      'ci_post_xcodebuild.sh skips cleanly outside archive runs even with missing paths',
      () {
        final result = Process.runSync(
          '/bin/sh',
          [postXcodebuild.path],
          environment: {'CI_XCODEBUILD_ACTION': 'build'},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
      },
    );

    test(
      'ci_post_xcodebuild.sh fails loudly during archive runs if archive/binary is absent',
      () {
        final result = Process.runSync(
          '/bin/sh',
          [postXcodebuild.path],
          environment: {
            'CI_XCODEBUILD_ACTION': 'archive',
            'CI_PRIMARY_REPOSITORY_PATH': '/nonexistent/repo',
            'CI_ARCHIVE_PATH': '/nonexistent/archive.xcarchive',
          },
        );
        expect(result.exitCode, isNot(0));
      },
    );

    test(
      'project.pbxproj Crashlytics build phase invokes FirebaseCrashlytics/run, not --validate',
      () {
        final pbxproj = File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();
        final phaseMatch = RegExp(
          r'A1B2C3D4E5F6A7B8C9D0E1F2 /\* \[firebase_crashlytics\] Upload dSYM \*/ = \{[\s\S]*?\n\t\t\};',
        ).firstMatch(pbxproj);
        expect(phaseMatch, isNotNull);
        final phase = phaseMatch!.group(0)!;
        expect(phase, contains(r'${PODS_ROOT}/FirebaseCrashlytics/run'));
        expect(phase, isNot(contains('--validate')));
      },
    );
  });

  group('M3: firebase.json iOS configuration consistency', () {
    test(
      'firebase.json matches live iOS App ID in GoogleService-Info.plist and firebase_options.dart',
      () {
        final firebaseJson =
            jsonDecode(File('firebase.json').readAsStringSync())
                as Map<String, dynamic>;
        final platforms =
            (firebaseJson['flutter'] as Map<String, dynamic>)['platforms']
                as Map<String, dynamic>;
        final iosDefault =
            (platforms['ios'] as Map<String, dynamic>)['default']
                as Map<String, dynamic>;
        final dartConfigs =
            ((platforms['dart']
                        as Map<String, dynamic>)['lib/firebase_options.dart']
                    as Map<String, dynamic>)['configurations']
                as Map<String, dynamic>;

        expect(iosDefault['appId'], expectedIosAppId);
        expect(iosDefault['uploadDebugSymbols'], isTrue);
        expect(dartConfigs['ios'], expectedIosAppId);

        final plist = File(
          'ios/Runner/GoogleService-Info.plist',
        ).readAsStringSync();
        expect(plist, contains('<string>$expectedIosAppId</string>'));

        final options = File('lib/firebase_options.dart').readAsStringSync();
        expect(options, contains("appId: '$expectedIosAppId'"));
      },
    );
  });
}
