// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/package_config_source.dart';
import 'package:synthex_lint/src/common/path_matcher.dart';
import 'package:synthex_lint/src/common/rule_keys.dart';
import 'package:synthex_lint/src/common/rule_provider.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/placement/domain/placement_config.dart';
import 'package:synthex_lint/src/rules/placement/infrastructure/add_supertype.dart';
import 'package:synthex_lint/src/rules/placement/infrastructure/placement_resolution.dart';
import 'package:synthex_lint/src/rules/placement/placement_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../support/correction_testing.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddSupertypeTest);
    defineReflectiveTests(AddSupertypeChoiceTest);
  });
}

class _FixedProvider implements RuleProvider<PlacementResolution> {
  _FixedProvider(this.config);

  final PlacementConfig? config;
  final PathMatcher matcher = GlobPathMatcher();
  final PackageConfigSource source = PackageConfigSource(
    ruleKey: placementRuleName,
  );

  @override
  PlacementResolution? resolve(RuleContext context) =>
      PlacementResolution(config: config, matcher: matcher, source: source);
}

PlacementConfig _config(List<String> mustHaveSupertype) => PlacementConfig(
  version: 1,
  severity: RuleSeverity.info,
  placements: [
    Placement(
      files: const ['lib/test.dart'],
      mustHaveSupertype: mustHaveSupertype,
    ),
  ],
);

/// Drives the correction through the analyzer's own machinery: build a context
/// for the diagnostic, compute the edits, apply them, and assert the resulting
/// source.
///
/// The rule requires a single supertype, so the fix can add it.
@reflectiveTest
class AddSupertypeTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PlacementRule(
      provider: _FixedProvider(_config(const ['Repository'])),
    );
    super.setUp();
  }

  Future<void> test_fix_creates_the_implements_clause() async {
    await assertDiagnostics(
      r'''
class Repository {}
class FakeRepository {}
''',
      [lint(6, 10), lint(26, 14)],
    );

    final fixed = await applyFix(
      result: result,
      code: placementRuleName,
      offset: 26,
      create: AddSupertype.new,
    );

    expect(fixed, r'''
class Repository {}
class FakeRepository implements Repository {}
''');
  }

  Future<void> test_fix_appends_to_an_existing_clause() async {
    await assertDiagnostics(
      r'''
class Repository {}
class FakeRepository implements Comparable<FakeRepository> {
  @override
  int compareTo(FakeRepository other) => 0;
}
''',
      [lint(6, 10), lint(26, 14)],
    );

    final fixed = await applyFix(
      result: result,
      code: placementRuleName,
      offset: 26,
      create: AddSupertype.new,
    );

    expect(fixed, r'''
class Repository {}
class FakeRepository implements Comparable<FakeRepository>, Repository {
  @override
  int compareTo(FakeRepository other) => 0;
}
''');
  }
}

/// The rule accepts one of several supertypes, so the fix has no single
/// supertype to add and must not be offered.
@reflectiveTest
class AddSupertypeChoiceTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PlacementRule(
      provider: _FixedProvider(_config(const ['Repository', 'DataSource'])),
    );
    super.setUp();
  }

  Future<void> test_fix_is_not_offered_for_a_choice_of_supertypes() async {
    await assertDiagnostics(
      r'''
class Repository {}
class FakeRepository {}
''',
      [lint(6, 10), lint(26, 14)],
    );

    final fixed = await applyFix(
      result: result,
      code: placementRuleName,
      offset: 26,
      create: AddSupertype.new,
    );

    expect(fixed, isNot(contains('implements')));
  }
}
