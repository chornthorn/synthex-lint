// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:synthex_lint/src/rules/placement/placement_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PlacementWorkspaceConfigTest);
  });
}

/// Covers the real `PlacementProvider`, and through it `PackageConfigSource`:
/// the `placement` key of `pubspec.yaml`, the dedicated config files, and which
/// of them wins.
@reflectiveTest
class PlacementWorkspaceConfigTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PlacementRule();
    super.setUp();
  }

  Future<void> test_readsDedicatedYamlFile() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
placement:
  version: 1
  placements:
    - files: ["lib/test.dart"]
      classesMustEndWith: ViewModel
''');

    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [
        lint(6, 9, messageContainsAll: ["'ViewModel'"]),
      ],
    );
  }

  Future<void> test_readsPubspecKey() async {
    updateTestPubspecFile('''
name: test

synthex_lint:
  placement:
    version: 1
    placements:
      - files: ["lib/test.dart"]
        classesMustEndWith: ViewModel
''');

    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [
        lint(6, 9, messageContainsAll: ["'ViewModel'"]),
      ],
    );
  }

  Future<void> test_dedicatedFileWinsOverPubspec() async {
    newFile('$testPackageRootPath/synthex_lint.yaml', '''
placement:
  version: 1
  placements:
    - files: ["lib/test.dart"]
      classesMustEndWith: ViewModel
''');
    updateTestPubspecFile('''
name: test

synthex_lint:
  placement:
    version: 1
    placements:
      - files: ["lib/test.dart"]
        classesMustEndWith: Screen
''');

    // The file's requirement is enforced, the pubspec's is not.
    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [
        lint(6, 9, messageContainsAll: ["'ViewModel'"]),
      ],
    );
  }

  Future<void> test_brokenConfigNamesItsSource() async {
    updateTestPubspecFile('''
name: test

synthex_lint:
  placement:
    version: 1
    placements: []
''');

    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [
        lint(
          0,
          0,
          messageContainsAll: ["pubspec.yaml 'synthex_lint.placement'"],
        ),
      ],
    );
  }

  Future<void> test_missingConfigKeepsRuleInert() async {
    await assertNoDiagnostics(r'''
class HomeBadge {}
''');
  }
}
