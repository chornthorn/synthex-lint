// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/package_config_source.dart';
import 'package:synthex_lint/src/common/path_matcher.dart';
import 'package:synthex_lint/src/common/rule_keys.dart';
import 'package:synthex_lint/src/common/rule_provider.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/placement/domain/placement_config.dart';
import 'package:synthex_lint/src/rules/placement/infrastructure/placement_resolution.dart';
import 'package:synthex_lint/src/rules/placement/placement_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PlacementTest);
  });
}

/// Injects a fixed config so rule tests do not need a file system.
///
/// The resolution still carries the real matcher and config source, so the
/// analyzed file's path comes from the analysis context as it does in
/// production.
class _FixedPlacementProvider implements RuleProvider<PlacementResolution> {
  _FixedPlacementProvider({this.config});

  PlacementConfig? config;
  List<String> errors = const [];

  final PathMatcher matcher = GlobPathMatcher();
  final PackageConfigSource source = PackageConfigSource(
    ruleKey: placementRuleName,
  );

  @override
  PlacementResolution? resolve(RuleContext context) => PlacementResolution(
    config: config,
    matcher: matcher,
    source: source,
    errors: errors,
  );
}

PlacementConfig _config(
  List<Placement> placements, {
  RuleSeverity severity = RuleSeverity.info,
}) => PlacementConfig(version: 1, severity: severity, placements: placements);

@reflectiveTest
class PlacementTest extends AnalysisRuleTest {
  late _FixedPlacementProvider _provider;

  @override
  void setUp() {
    _provider = _FixedPlacementProvider(
      config: _config([
        Placement(
          files: const ['lib/test.dart'],
          classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
        ),
      ]),
    );
    rule = PlacementRule(provider: _provider);
    super.setUp();
  }

  Future<void> test_flags_class_with_wrong_name() async {
    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [lint(6, 9)],
    );
  }

  Future<void> test_allows_class_with_required_name() async {
    await assertNoDiagnostics(r'''
class HomeViewModel {}
''');
  }

  Future<void> test_allows_private_class_exempt_from_the_suffix() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/test.dart'],
        classesMustEndWith: const [
          RequiredSuffix(suffix: 'UseCase', excludesPrivate: true),
        ],
      ),
    ]);

    await assertNoDiagnostics(r'''
class _Cache {}
''');
  }

  Future<void> test_flags_public_class_missing_an_exempting_suffix() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/test.dart'],
        classesMustEndWith: const [
          RequiredSuffix(suffix: 'UseCase', excludesPrivate: true),
        ],
      ),
    ]);

    await assertDiagnostics(
      r'''
class LoadProfile {}
''',
      [
        lint(6, 11, messageContainsAll: ["name must end with 'UseCase'"]),
      ],
    );
  }

  Future<void> test_ignores_unmatched_files() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/src/other/**'],
        classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
      ),
    ]);

    await assertNoDiagnostics(r'''
class HomeBadge {}
''');
  }

  Future<void> test_ignores_exempt_file() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/**'],
        exempt: const ['lib/test.dart'],
        classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
      ),
    ]);

    await assertNoDiagnostics(r'''
class HomeBadge {}
''');
  }

  Future<void> test_flags_missing_supertype() async {
    newFile('/home/test/lib/base.dart', 'class Repository {}');
    _provider.config = _config([
      Placement(
        files: const ['lib/test.dart'],
        mustHaveSupertype: const ['Repository'],
      ),
    ]);

    // Only the repository that does not implement the contract is flagged.
    await assertDiagnostics(
      r'''
import 'base.dart';

class FakeRepository {}

class InMemoryRepository implements Repository {}
''',
      [lint(27, 14)],
    );
  }

  Future<void> test_flags_forbidden_supertype() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/test.dart'],
        mustNotHaveSupertype: const ['ChangeNotifier'],
      ),
    ]);

    await assertDiagnostics(
      r'''
class ChangeNotifier {}
class MyViewModel extends ChangeNotifier {}
''',
      [lint(30, 11)],
    );
  }

  Future<void> test_reports_config_errors() async {
    _provider.config = null;
    _provider.errors = ['boom'];

    await assertDiagnostics(
      r'''
class HomeBadge {}
''',
      [lint(0, 0)],
    );
  }

  Future<void> test_ignore_comment_suppresses() async {
    await assertNoDiagnostics(r'''
// ignore: placement
class HomeBadge {}
''');
  }

  Future<void> test_ignore_comment_suppresses_error_severity() async {
    _provider.config = _config([
      Placement(
        files: const ['lib/test.dart'],
        classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
      ),
    ], severity: RuleSeverity.error);

    await assertNoDiagnostics(r'''
// ignore: placement
class HomeBadge {}
''');
  }

  void test_severity_codes() {
    expect(
      PlacementRule.codeFor(RuleSeverity.info).severity,
      DiagnosticSeverity.INFO,
    );
    expect(
      PlacementRule.codeFor(RuleSeverity.warning).severity,
      DiagnosticSeverity.WARNING,
    );
    expect(
      PlacementRule.codeFor(RuleSeverity.error).severity,
      DiagnosticSeverity.ERROR,
    );
    // All severities share the display name, so one ignore comment covers
    // every severity of the rule.
    expect(PlacementRule.infoCode.lowerCaseName, placementRuleName);
    expect(PlacementRule.warningCode.lowerCaseName, placementRuleName);
    expect(PlacementRule.errorCode.lowerCaseName, placementRuleName);
  }
}
