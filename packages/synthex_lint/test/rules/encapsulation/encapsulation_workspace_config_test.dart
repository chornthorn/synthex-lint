// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:synthex_lint/src/rules/encapsulation/encapsulation_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EncapsulationWorkspaceConfigTest);
  });
}

/// Covers the real `EncapsulationProvider`, and through it
/// `PackageConfigSource`: the `encapsulation` key of `pubspec.yaml`, the
/// dedicated config files, and which of them wins.
@reflectiveTest
class EncapsulationWorkspaceConfigTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = EncapsulationRule();
    super.setUp();
  }

  Future<void> test_readsDedicatedYamlFile() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
encapsulation:
  version: 1
  encapsulations:
    - files: ["lib/test.dart"]
      requirements:
        fieldsPrivate: true
''');

    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_readsPubspecKey() async {
    updateTestPubspecFile('''
name: test

synthex_lint:
  encapsulation:
    version: 1
    severity: error
    encapsulations:
      - files: ["lib/test.dart"]
        requirements:
          fieldsPrivate: true
''');

    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_dedicatedFileWinsOverPubspec() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
encapsulation:
  version: 1
  encapsulations:
    - files: ["lib/test.dart"]
      requirements:
        fieldsPrivate: true
        privateFieldsFinal: false
        noPublicSetters: false
''');
    updateTestPubspecFile('''
name: test

synthex_lint:
  encapsulation:
    version: 1
    encapsulations:
      - files: ["lib/test.dart"]
        requirements:
          fieldsPrivate: false
          privateFieldsFinal: false
          noPublicSetters: true
''');

    // The file's requirements are enforced, the pubspec's are not: the public
    // field is reported, the public setter is not.
    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
  set title(String value) {}
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_brokenConfigNamesItsSource() async {
    updateTestPubspecFile('''
name: test

synthex_lint:
  encapsulation:
    version: 1
    encapsulations: []
''');

    await assertDiagnostics(
      r'''
class HomeViewModel {}
''',
      [
        lint(
          0,
          0,
          messageContainsAll: ["pubspec.yaml 'synthex_lint.encapsulation'"],
        ),
      ],
    );
  }

  Future<void> test_readsDocumentLevelKeys() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
version: 1
severity: warning
encapsulation:
  encapsulations:
    - files: ["lib/test.dart"]
      requirements:
        fieldsPrivate: true
''');

    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_reportsAnUnknownSection() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
encapsulationt:
  version: 1
''');

    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [
        lint(
          0,
          0,
          messageContainsAll: [
            "unknown key 'encapsulationt'",
            'architecture, encapsulation, placement',
            'severity/version',
          ],
        ),
      ],
    );
  }

  Future<void> test_missingConfigKeepsRuleInert() async {
    await assertNoDiagnostics(r'''
class HomeViewModel {
  int count = 0;
}
''');
  }
}
