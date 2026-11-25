import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/firebase_options.dart';
import 'package:xml/xml.dart';

/// Minimal OpenStep ASCII plist parser for Xcode `project.pbxproj` files.
///
/// Parses comments, dictionaries, arrays, quoted strings with escapes, and
/// unquoted atoms into Dart Maps, Lists, and Strings so tests can navigate
/// Xcode's semantic target/build-phase graph instead of regex-matching text.
class _OpenStepPlistParser {
  _OpenStepPlistParser(this._source);

  final String _source;
  int _pos = 0;

  Object parse() {
    _skipWhitespaceAndComments();
    final value = _parseValue();
    _skipWhitespaceAndComments();
    if (!_isEof) {
      throw FormatException('Unexpected trailing input at $_pos');
    }
    return value;
  }

  bool get _isEof => _pos >= _source.length;

  void _skipWhitespaceAndComments() {
    while (!_isEof) {
      final ch = _source[_pos];
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        _pos++;
      } else if (ch == '/' && _pos + 1 < _source.length) {
        final next = _source[_pos + 1];
        if (next == '*') {
          _pos += 2;
          final end = _source.indexOf('*/', _pos);
          if (end == -1) {
            throw FormatException('Unterminated block comment at $_pos');
          }
          _pos = end + 2;
        } else if (next == '/') {
          _pos += 2;
          final end = _source.indexOf('\n', _pos);
          _pos = end == -1 ? _source.length : end + 1;
        } else {
          break;
        }
      } else {
        break;
      }
    }
  }

  Object _parseValue() {
    _skipWhitespaceAndComments();
    if (_isEof) {
      throw FormatException('Unexpected EOF at $_pos');
    }
    final ch = _source[_pos];
    if (ch == '{') return _parseDict();
    if (ch == '(') return _parseArray();
    if (ch == '"') return _parseQuotedString();
    return _parseUnquotedString();
  }

  Map<String, Object> _parseDict() {
    _expect('{');
    final map = <String, Object>{};
    while (true) {
      _skipWhitespaceAndComments();
      if (!_isEof && _source[_pos] == '}') {
        _pos++;
        return map;
      }
      final key = _parseString();
      _skipWhitespaceAndComments();
      _expect('=');
      final value = _parseValue();
      _skipWhitespaceAndComments();
      _expect(';');
      map[key] = value;
    }
  }

  List<Object> _parseArray() {
    _expect('(');
    final list = <Object>[];
    while (true) {
      _skipWhitespaceAndComments();
      if (!_isEof && _source[_pos] == ')') {
        _pos++;
        return list;
      }
      list.add(_parseValue());
      _skipWhitespaceAndComments();
      if (!_isEof && _source[_pos] == ',') {
        _pos++;
      }
    }
  }

  String _parseString() {
    _skipWhitespaceAndComments();
    if (!_isEof && _source[_pos] == '"') {
      return _parseQuotedString();
    }
    return _parseUnquotedString();
  }

  String _parseQuotedString() {
    _expect('"');
    final buf = StringBuffer();
    while (!_isEof) {
      final ch = _source[_pos++];
      if (ch == '"') return buf.toString();
      if (ch == r'\') {
        if (_isEof) {
          throw FormatException('Unterminated escape at $_pos');
        }
        final esc = _source[_pos++];
        switch (esc) {
          case 'n':
            buf.write('\n');
          case 'r':
            buf.write('\r');
          case 't':
            buf.write('\t');
          case '"':
            buf.write('"');
          case r'\':
            buf.write(r'\');
          default:
            buf.write(esc);
        }
      } else {
        buf.write(ch);
      }
    }
    throw FormatException('Unterminated quoted string at $_pos');
  }

  String _parseUnquotedString() {
    final start = _pos;
    while (!_isEof) {
      final ch = _source[_pos];
      if (ch == ' ' ||
          ch == '\t' ||
          ch == '\r' ||
          ch == '\n' ||
          ch == '{' ||
          ch == '}' ||
          ch == '(' ||
          ch == ')' ||
          ch == ';' ||
          ch == '=' ||
          ch == ',' ||
          ch == '"') {
        break;
      }
      if (ch == '/' &&
          _pos + 1 < _source.length &&
          (_source[_pos + 1] == '*' || _source[_pos + 1] == '/')) {
        break;
      }
      _pos++;
    }
    if (_pos == start) {
      throw FormatException('Unexpected character "${_source[_pos]}" at $_pos');
    }
    return _source.substring(start, _pos);
  }

  void _expect(String expected) {
    if (_isEof || _source[_pos] != expected) {
      throw FormatException('Expected "$expected" at $_pos');
    }
    _pos++;
  }
}

Map<String, String> _parseXmlPlistStrings(XmlDocument doc) {
  final dict = doc.rootElement.findElements('dict').single;
  final elements = dict.childElements.toList();
  final result = <String, String>{};
  for (var i = 0; i + 1 < elements.length; i += 2) {
    if (elements[i].name.local == 'key' &&
        elements[i + 1].name.local == 'string') {
      result[elements[i].innerText] = elements[i + 1].innerText;
    }
  }
  return result;
}

({
  Directory root,
  String repoPath,
  String archivePath,
  String plistPath,
  String dsymsPath,
  File uploadSymbolsStub,
})
_createFakeXcodeCloudEnv() {
  final root = Directory.systemTemp.createTempSync('ci_post_xcodebuild_test_');
  final repoPath = '${root.path}/repo';
  final archivePath = '${root.path}/archive.xcarchive';
  final plistPath = '$repoPath/ios/Runner/GoogleService-Info.plist';
  final dsymsPath = '$archivePath/dSYMs';
  final uploadSymbolsStub = File(
    '$repoPath/ios/Pods/FirebaseCrashlytics/upload-symbols',
  );

  File(plistPath)
    ..createSync(recursive: true)
    ..writeAsStringSync('<plist/>');
  Directory(dsymsPath).createSync(recursive: true);
  uploadSymbolsStub.createSync(recursive: true);

  return (
    root: root,
    repoPath: repoPath,
    archivePath: archivePath,
    plistPath: plistPath,
    dsymsPath: dsymsPath,
    uploadSymbolsStub: uploadSymbolsStub,
  );
}

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
      'ci_post_xcodebuild.sh synchronously runs upload-symbols with archive dSYMs and no --validate',
      () {
        final env = _createFakeXcodeCloudEnv();
        addTearDown(() => env.root.deleteSync(recursive: true));

        final argsFile = File('${env.root.path}/recorded_args.txt');
        final doneFile = File('${env.root.path}/upload_done.txt');
        env.uploadSymbolsStub.writeAsStringSync('''#!/bin/sh
set -eu
for arg in "\$@"; do
  printf '%s\\n' "\$arg" >> '${argsFile.path}'
done
sleep 0.2
printf 'completed\\n' > '${doneFile.path}'
''');
        final chmod = Process.runSync('chmod', [
          '+x',
          env.uploadSymbolsStub.path,
        ]);
        expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

        final result = Process.runSync(
          '/bin/sh',
          [postXcodebuild.path],
          environment: {
            'CI_XCODEBUILD_ACTION': 'archive',
            'CI_PRIMARY_REPOSITORY_PATH': env.repoPath,
            'CI_ARCHIVE_PATH': env.archivePath,
          },
        );

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          doneFile.existsSync(),
          isTrue,
          reason:
              'ci_post_xcodebuild.sh must wait synchronously for upload-symbols to finish',
        );
        expect(argsFile.readAsLinesSync(), [
          '-gsp',
          env.plistPath,
          '-p',
          'ios',
          env.dsymsPath,
        ]);
      },
    );

    test(
      'ci_post_xcodebuild.sh propagates non-zero exit codes from upload-symbols',
      () {
        final env = _createFakeXcodeCloudEnv();
        addTearDown(() => env.root.deleteSync(recursive: true));

        env.uploadSymbolsStub.writeAsStringSync('''#!/bin/sh
echo "simulated upload failure" >&2
exit 42
''');
        final chmod = Process.runSync('chmod', [
          '+x',
          env.uploadSymbolsStub.path,
        ]);
        expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

        final result = Process.runSync(
          '/bin/sh',
          [postXcodebuild.path],
          environment: {
            'CI_XCODEBUILD_ACTION': 'archive',
            'CI_PRIMARY_REPOSITORY_PATH': env.repoPath,
            'CI_ARCHIVE_PATH': env.archivePath,
          },
        );

        expect(result.exitCode, 42);
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
      'project.pbxproj Runner target attaches Crashlytics run build phase without --validate',
      () {
        final plist =
            _OpenStepPlistParser(
                  File(
                    'ios/Runner.xcodeproj/project.pbxproj',
                  ).readAsStringSync(),
                ).parse()
                as Map<String, Object>;
        final objects = plist['objects'] as Map<String, Object>;
        final rootObjectId = plist['rootObject'] as String;
        final project = objects[rootObjectId] as Map<String, Object>;
        expect(project['isa'], 'PBXProject');

        final targetIds = (project['targets'] as List<Object>).cast<String>();
        final runnerTarget = targetIds
            .map((id) => objects[id] as Map<String, Object>)
            .singleWhere(
              (target) =>
                  target['isa'] == 'PBXNativeTarget' &&
                  target['name'] == 'Runner',
            );

        final phaseIds = (runnerTarget['buildPhases'] as List<Object>)
            .cast<String>();
        final crashlyticsPhases = phaseIds
            .map((id) => objects[id] as Map<String, Object>)
            .where(
              (phase) =>
                  phase['isa'] == 'PBXShellScriptBuildPhase' &&
                  phase['name'] == '[firebase_crashlytics] Upload dSYM',
            )
            .toList();

        expect(crashlyticsPhases, hasLength(1));
        final script = (crashlyticsPhases.single['shellScript'] as String)
            .trim();
        expect(script, r'"${PODS_ROOT}/FirebaseCrashlytics/run"');
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

        final plistDoc = XmlDocument.parse(
          File('ios/Runner/GoogleService-Info.plist').readAsStringSync(),
        );
        final plistValues = _parseXmlPlistStrings(plistDoc);
        expect(plistValues['GOOGLE_APP_ID'], expectedIosAppId);

        expect(DefaultFirebaseOptions.ios.appId, expectedIosAppId);
      },
    );
  });
}
