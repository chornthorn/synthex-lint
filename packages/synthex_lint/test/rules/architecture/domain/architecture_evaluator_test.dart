import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/package_paths.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_evaluator.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_schema.dart';
import 'package:test/test.dart';

const _schema = ArchitectureSchema(
  version: 1,
  severity: RuleSeverity.warning,
  layers: [
    ArchitectureLayer(
      name: 'domain',
      files: ['lib/src/domain/**'],
      forbiddenImports: [
        ForbiddenImport('dart:io', severity: RuleSeverity.error),
        ForbiddenImport('package:flutter/**'),
      ],
    ),
    ArchitectureLayer(
      name: 'data',
      files: ['lib/src/data/**'],
      mayImport: ['domain'],
      forbiddenImports: [ForbiddenImport('package:http/**')],
      forbiddenImportSeverity: RuleSeverity.info,
    ),
    ArchitectureLayer(
      name: 'presentation',
      files: ['lib/src/presentation/**'],
      mayImport: ['domain', 'data'],
      severity: RuleSeverity.error,
      mayImportSeverity: RuleSeverity.warning,
    ),
    ArchitectureLayer(
      name: 'shared',
      files: ['lib/src/shared/**'],
      severity: RuleSeverity.error,
      forbiddenImports: [ForbiddenImport('dart:io')],
    ),
  ],
);

final _evaluator = ArchitectureEvaluator(
  schema: _schema,
  matcher: GlobPathMatcher(),
);

FileFacts _factsFor(String path, List<String> uris) => FileFacts(
  path: path,
  imports: [
    for (final uri in uris)
      ImportFacts(
        uri: uri,
        target: classifyImport(
          uri: uri,
          importingFilePath: path,
          packageName: 'app',
        ),
      ),
  ],
);

void main() {
  group('evaluation', () {
    test('flags an import of a layer that is not allowed', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/data/repo.dart', ['../presentation/home.dart']),
      );

      expect(violations, hasLength(1));
      expect(violations.single.uri, '../presentation/home.dart');
      expect(
        violations.single.message,
        contains("Layer 'data' may not import 'presentation'"),
      );
    });

    test('allows imports of layers listed in mayImport', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/data/repo.dart', ['../domain/entity.dart']),
      );

      expect(violations, isEmpty);
    });

    test('allows imports within the same layer', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/domain/entity.dart', ['./value.dart']),
      );

      expect(violations, isEmpty);
    });

    test('flags forbidden external imports', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/domain/entity.dart', [
          'dart:io',
          'package:flutter/material.dart',
        ]),
      );

      expect(violations, hasLength(2));
      expect(
        violations[0].message,
        contains("Layer 'domain' forbids import 'dart:io'"),
      );
      expect(violations[1].message, contains('package:flutter/material.dart'));
    });

    test('allows external imports that are not forbidden', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/domain/entity.dart', [
          'package:collection/collection.dart',
        ]),
      );

      expect(violations, isEmpty);
    });

    test('ignores files that no layer owns', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/main.dart', ['package:app/src/data/repo.dart']),
      );

      expect(violations, isEmpty);
    });

    test('flags violations per import, in file order', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/domain/entity.dart', [
          '../data/repo.dart',
          'dart:io',
          '../presentation/home.dart',
        ]),
      );

      expect(violations, hasLength(3));
      expect(violations[0].uri, '../data/repo.dart');
      expect(violations[1].uri, 'dart:io');
      expect(violations[2].uri, '../presentation/home.dart');
    });
  });

  group('severity precedence', () {
    test('a per-pattern severity wins, else the schema default applies', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/domain/entity.dart', [
          'dart:io',
          'package:flutter/material.dart',
        ]),
      );

      expect(violations[0].severity, RuleSeverity.error);
      expect(violations[1].severity, RuleSeverity.warning);
    });

    test('a layer forbidden-import severity applies without a pattern one', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/data/repo.dart', ['package:http/http.dart']),
      );

      expect(violations.single.severity, RuleSeverity.info);
    });

    test('boundary violations fall back to the schema severity', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/data/repo.dart', ['../presentation/home.dart']),
      );

      expect(violations.single.severity, RuleSeverity.warning);
    });

    test('a layer mayImport severity overrides the layer severity', () {
      final violations = _evaluator.evaluate(
        _factsFor('lib/src/presentation/home.dart', ['../shared/theme.dart']),
      );

      expect(violations.single.severity, RuleSeverity.warning);
    });

    test('a layer severity applies to forbidden and boundary violations', () {
      final forbidden = _evaluator.evaluate(
        _factsFor('lib/src/shared/theme.dart', ['dart:io']),
      );
      expect(forbidden.single.severity, RuleSeverity.error);

      final boundary = _evaluator.evaluate(
        _factsFor('lib/src/shared/theme.dart', ['../domain/entity.dart']),
      );
      expect(boundary.single.severity, RuleSeverity.error);
    });
  });
}
