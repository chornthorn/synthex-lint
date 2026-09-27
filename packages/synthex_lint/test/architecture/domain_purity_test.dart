import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Imports that pure code must never have.
///
/// Pure code may use pure utility packages such as `path` and `glob`; it must
/// not reach for IO, the analyzer, or the plugin framework.
const _forbiddenImports = [
  'dart:io',
  'package:analyzer',
  'package:analysis_server_plugin',
];

/// Guards the clean architecture layering: every `domain/` folder under
/// `lib/src` is pure Dart — testable without a file system, an analysis
/// context, or a running server, no matter which rule it belongs to.
///
/// `lib/src/common/` is deliberately not covered by the purity rule: it holds
/// helpers shared by rules, and some of them
/// (`package_config_source.dart`) read configuration through the analyzer's
/// file system by design. What `src/common/` may not do is depend on a single
/// rule — the second test in this file enforces that.
void main() {
  test('domain code stays free of IO, analyzer, and plugin imports', () {
    final src = Directory('lib/src');
    expect(src.existsSync(), isTrue, reason: 'run tests from the package root');

    final domainFiles = src
        .listSync(recursive: true)
        .whereType<Directory>()
        .where((directory) => p.basename(directory.path) == 'domain')
        .expand((directory) => directory.listSync(recursive: true))
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(
      domainFiles,
      isNotEmpty,
      reason: 'no domain folders found under lib/src',
    );

    final offenders = <String>[];
    for (final file in domainFiles) {
      var lineNumber = 0;
      for (final line in file.readAsLinesSync()) {
        lineNumber++;
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        for (final forbidden in _forbiddenImports) {
          if (trimmed.contains(forbidden)) {
            offenders.add('${file.path}:$lineNumber -> $trimmed');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Pure code must stay pure:\n${offenders.join('\n')}',
    );
  });

  test('common helpers stay rule-agnostic', () {
    final common = Directory('lib/src/common');
    expect(common.existsSync(), isTrue, reason: 'lib/src/common is missing');

    final offenders = <String>[];
    for (final file
        in common
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      var lineNumber = 0;
      for (final line in file.readAsLinesSync()) {
        lineNumber++;
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        // A shared helper must not reach into one rule's folder; promote the
        // needed piece to `src/common/` instead.
        if (trimmed.contains('rules/')) {
          offenders.add('${file.path}:$lineNumber -> $trimmed');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Helpers shared by rules must not depend on a single rule:\n'
          '${offenders.join('\n')}',
    );
  });
}
