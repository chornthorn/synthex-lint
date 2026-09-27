// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:synthex_lint/src/rules/architecture/architecture_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ArchitectureWorkspaceConfigTest);
  });
}

/// Covers the real `ArchitectureProvider`, and through it `PackageConfigSource`:
/// YAML and JSON schema files, the `architecture` key of `pubspec.yaml`, which
/// of them wins, and the package name used to classify `package:`
/// self-imports.
@reflectiveTest
class ArchitectureWorkspaceConfigTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ArchitectureRule();
    super.setUp();
  }

  Future<void> test_readsDedicatedYamlFile() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
architecture:
  version: 1
  layers:
    - name: domain
      files: ["lib/**"]
      forbiddenImports:
        - dart:io
''');

    await assertDiagnostics(
      r'''
export 'dart:io';
''',
      [lint(0, 17)],
    );
  }

  Future<void> test_readsPubspecKey() async {
    updateTestPubspecFile('''
name: test

synthex_lint:
  architecture:
    version: 1
    layers:
      - name: domain
        files: ["lib/**"]
        forbiddenImports:
          - dart:io
''');

    await assertDiagnostics(
      r'''
export 'dart:io';
''',
      [lint(0, 17)],
    );
  }

  Future<void> test_dedicatedFileWinsOverPubspec() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
architecture:
  version: 1
  layers:
    - name: domain
      files: ["lib/**"]
      forbiddenImports:
        - package:flutter/**
''');
    updateTestPubspecFile('''
name: test

synthex_lint:
  architecture:
    version: 1
    layers:
      - name: domain
        files: ["lib/**"]
        forbiddenImports:
          - dart:io
''');

    // The file's schema is enforced, so `dart:io` is not forbidden.
    await assertNoDiagnostics(r'''
export 'dart:io';
''');
  }

  Future<void> test_brokenSchemaNamesItsSource() async {
    newFile(
      '$testPackageRootPath/synthex_lint.yaml',
      'architecture:\n  version: 1\n',
    );

    await assertDiagnostics(
      r'''
export 'dart:io';
''',
      [
        lint(0, 0, messageContainsAll: ["synthex_lint.yaml 'architecture'"]),
      ],
    );
  }

  Future<void> test_missingConfigKeepsRuleInert() async {
    await assertNoDiagnostics(r'''
export 'dart:io';
''');
  }

  Future<void> test_classifiesSelfImportsUsingThePubspecName() async {
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    updateTestPubspecFile('''
name: test

synthex_lint:
  architecture:
    version: 1
    layers:
      - name: data
        files: ["lib/src/data/**"]
      - name: presentation
        files: ["lib/test.dart"]
''');

    await assertDiagnostics(
      r'''
export 'package:test/src/data/repo.dart';
''',
      [
        lint(0, 41, messageContainsAll: ["may not import 'data'"]),
      ],
    );
  }
}
