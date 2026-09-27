// ignore_for_file: avoid_print

import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/package_paths.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_evaluator.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_schema.dart';

/// Measures the pure part of the `architecture` rule: pattern matching and
/// evaluation. The analyzer-side parts (schema file reads, reporting) are IO
/// bound and deliberately not benchmarked here.
///
/// ```sh
/// dart run benchmark/architecture_evaluator.dart
/// ```
void main() {
  _benchmarkMatcher();
  _benchmarkEvaluator();
}

void _benchmarkMatcher() {
  const patterns = ['lib/src/domain/**', 'package:flutter/**', 'dart:io'];
  final values = [
    for (var i = 0; i < 250; i++) 'lib/src/domain/file_$i.dart',
    for (var i = 0; i < 250; i++) 'package:flutter/material.dart',
    for (var i = 0; i < 250; i++) 'package:collection/collection.dart',
    for (var i = 0; i < 250; i++) 'lib/src/data/file_$i.dart',
  ];
  final matcher = GlobPathMatcher();

  const rounds = 200;
  var matches = 0;
  final watch = Stopwatch()..start();
  for (var round = 0; round < rounds; round++) {
    for (final pattern in patterns) {
      for (final value in values) {
        if (matcher.matches(pattern, value)) matches++;
      }
    }
  }
  watch.stop();

  final calls = rounds * patterns.length * values.length;
  print(
    'matcher: $calls calls in ${watch.elapsedMilliseconds} ms '
    '(${(watch.elapsedMicroseconds * 1000 / calls).toStringAsFixed(1)} ns/call, '
    '$matches matches)',
  );
}

void _benchmarkEvaluator() {
  const layers = 12;
  const files = 5000;
  const importsPerFile = 25;

  final schema = _syntheticSchema(layers: layers);
  final evaluator = ArchitectureEvaluator(
    schema: schema,
    matcher: GlobPathMatcher(),
  );
  final facts = _syntheticFacts(
    files: files,
    layers: layers,
    importsPerFile: importsPerFile,
  );

  // Warm up the JIT so the measured loop is compiled.
  for (final fileFacts in facts.take(500)) {
    evaluator.evaluate(fileFacts);
  }

  var violations = 0;
  final watch = Stopwatch()..start();
  for (final fileFacts in facts) {
    violations += evaluator.evaluate(fileFacts).length;
  }
  watch.stop();

  print(
    'evaluator: $files files x $importsPerFile imports in '
    '${watch.elapsedMilliseconds} ms '
    '(${(watch.elapsedMicroseconds / files).toStringAsFixed(1)} µs/file, '
    '$violations violations)',
  );
}

ArchitectureSchema _syntheticSchema({required int layers}) =>
    ArchitectureSchema(
      version: 1,
      severity: RuleSeverity.warning,
      layers: [
        for (var i = 0; i < layers; i++)
          ArchitectureLayer(
            name: 'layer$i',
            files: ['lib/src/layer$i/**', 'lib/generated/layer$i/**'],
            mayImport: [if (i > 0) 'layer${i - 1}'],
            forbiddenImports: [ForbiddenImport('package:pkg$i/**')],
          ),
      ],
    );

List<FileFacts> _syntheticFacts({
  required int files,
  required int layers,
  required int importsPerFile,
}) => [
  for (var i = 0; i < files; i++)
    _fileFacts(i, layers: layers, importsPerFile: importsPerFile),
];

FileFacts _fileFacts(
  int index, {
  required int layers,
  required int importsPerFile,
}) {
  final path = 'lib/src/layer${index % layers}/file_$index.dart';
  return FileFacts(
    path: path,
    imports: [
      for (var j = 0; j < importsPerFile; j++)
        ImportFacts(
          uri: 'import_$j',
          target: classifyImport(
            uri: j.isEven
                ? 'package:app/src/layer${(index + j) % layers}/other.dart'
                : '../layer${(index + j + 1) % layers}/other.dart',
            importingFilePath: path,
            packageName: 'app',
          ),
        ),
    ],
  );
}
