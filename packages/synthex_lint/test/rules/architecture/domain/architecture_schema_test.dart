import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_schema.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  test('parses a valid schema', () {
    final result = parseArchitectureSchema({
      'version': 1,
      'severity': 'warning',
      'layers': [
        {
          'name': 'domain',
          'files': ['lib/src/domain/**'],
          'forbiddenImports': ['dart:io'],
        },
        {
          'name': 'data',
          'files': ['lib/src/data/**'],
          'mayImport': ['domain'],
          'severity': {
            'default': 'info',
            'mayImport': 'error',
            'forbiddenImports': 'warning',
          },
        },
      ],
    }, matcher: matcher);

    expect(result.errors, isEmpty);
    final schema = result.schema!;
    expect(schema.version, architectureSchemaVersion);
    expect(schema.severity, RuleSeverity.warning);
    expect(schema.layers, hasLength(2));
    expect(schema.layers[0].name, 'domain');
    expect(schema.layers[0].files, ['lib/src/domain/**']);
    expect(schema.layers[0].mayImport, isEmpty);
    expect(schema.layers[0].forbiddenImports.single.pattern, 'dart:io');
    expect(schema.layers[0].forbiddenImports.single.severity, isNull);
    expect(schema.layers[0].severity, isNull);
    expect(schema.layers[1].mayImport, ['domain']);
    expect(schema.layers[1].severity, RuleSeverity.info);
    expect(schema.layers[1].mayImportSeverity, RuleSeverity.error);
    expect(schema.layers[1].forbiddenImportSeverity, RuleSeverity.warning);
  });

  test('defaults to info severity', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
        },
      ],
    }, matcher: matcher);

    expect(result.schema!.severity, RuleSeverity.info);
  });

  test('parses a layer severity string and per-pattern severities', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'domain',
          'files': ['lib/src/domain/**'],
          'severity': 'error',
          'forbiddenImports': [
            'dart:io',
            {'uri': 'package:flutter/**', 'severity': 'warning'},
          ],
        },
      ],
    }, matcher: matcher);

    expect(result.errors, isEmpty);
    final layer = result.schema!.layers.single;
    expect(layer.severity, RuleSeverity.error);
    expect(layer.forbiddenImports, hasLength(2));
    expect(layer.forbiddenImports[0].severity, isNull);
    expect(layer.forbiddenImports[1].pattern, 'package:flutter/**');
    expect(layer.forbiddenImports[1].severity, RuleSeverity.warning);
  });

  test('rejects an invalid severity value', () {
    final result = parseArchitectureSchema({
      'severity': 'fatal',
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("invalid severity 'fatal'"));
  });

  test('rejects unknown severity object keys', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
          'severity': {'default': 'info', 'warnings': 'error'},
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("unknown key 'warnings'"));
  });

  test('rejects a forbidden import object without a uri', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
          'forbiddenImports': [
            {'severity': 'error'},
          ],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("'uri' must be a non-empty string"));
  });

  test('rejects a non-object document', () {
    final result = parseArchitectureSchema('nope', matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors, ['The schema must be a map.']);
  });

  test('requires layers', () {
    final result = parseArchitectureSchema({'layers': []}, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, "'layers' must be a non-empty list.");
  });

  test('rejects an unsupported version', () {
    final result = parseArchitectureSchema({
      'version': 2,
      'layers': [
        {
          'name': 'a',
          'files': ['lib/**'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains('Unsupported version'));
  });

  test('rejects duplicate layer names', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
        },
        {
          'name': 'a',
          'files': ['lib/b/**'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("Duplicate layer name 'a'"));
  });

  test('rejects mayImport of an unknown layer', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/a/**'],
          'mayImport': ['nowhere'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("unknown layer 'nowhere'"));
  });

  test('rejects absolute patterns', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['/lib/a/**'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(
      result.errors.single,
      contains('must be relative to the package root'),
    );
  });

  test('rejects an invalid glob', () {
    final result = parseArchitectureSchema({
      'layers': [
        {
          'name': 'a',
          'files': ['lib/src/['],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains('invalid pattern'));
  });

  test('requires files on every layer', () {
    final result = parseArchitectureSchema({
      'layers': [
        {'name': 'a'},
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains("'files' is required"));
  });

  test('collects multiple errors', () {
    final result = parseArchitectureSchema({
      'layers': [
        {'name': 'a'},
        {
          'name': 'a',
          'files': ['lib/a/**'],
          'mayImport': ['ghost'],
        },
      ],
    }, matcher: matcher);

    expect(result.isValid, isFalse);
    expect(result.errors.length, greaterThanOrEqualTo(2));
  });
}
