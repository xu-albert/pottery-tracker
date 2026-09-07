import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Every domain Android's backup agent walks
/// (`FullBackup.getDirectoryForCriteriaDomain`). A section that excludes all
/// of them carries nothing of the app's.
const _everyDomain = {
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
  'device_root',
  'device_file',
  'device_database',
  'device_sharedpref',
};

/// The manifest and the rules file are the app's declared backup
/// configuration — the contract Android's backup agent consumes — read here
/// as the agent reads them: an `<exclude>` with no `path` names the whole
/// domain directory.
Map<String, Set<String>> _wholeDomainExcludes(XmlDocument rules) => {
  for (final section in rules.rootElement.childElements)
    section.name.local: {
      for (final rule in section.findElements('exclude'))
        if (rule.getAttribute('path') == null) rule.getAttribute('domain')!,
    },
};

void main() {
  final manifest = XmlDocument.parse(
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
  );
  final application = manifest.findAllElements('application').single;

  test('Google Drive backup stays off', () {
    expect(application.getAttribute('android:allowBackup'), 'false');
  });

  test('Android 12+ device transfer and cloud backup exclude every domain, '
      'and include nothing', () {
    final reference = application.getAttribute('android:dataExtractionRules');
    expect(reference, startsWith('@xml/'));
    final rules = XmlDocument.parse(
      File(
        'android/app/src/main/res/xml/${reference!.substring(5)}.xml',
      ).readAsStringSync(),
    );

    final excludes = _wholeDomainExcludes(rules);
    for (final section in const ['cloud-backup', 'device-transfer']) {
      expect(excludes[section], _everyDomain, reason: section);
      expect(
        rules.rootElement.findElements(section).single.findElements('include'),
        isEmpty,
        reason: section,
      );
    }
  });
}
