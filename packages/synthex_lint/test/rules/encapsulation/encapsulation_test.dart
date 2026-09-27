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
import 'package:synthex_lint/src/rules/encapsulation/domain/encapsulation_config.dart';
import 'package:synthex_lint/src/rules/encapsulation/encapsulation_rule.dart';
import 'package:synthex_lint/src/rules/encapsulation/infrastructure/encapsulation_resolution.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EncapsulationTest);
  });
}

/// Injects a fixed config so rule tests do not need a file system.
///
/// The resolution still carries the real matcher and config source, so the
/// analyzed file's path comes from the analysis context as it does in
/// production.
class _FixedConfigProvider implements RuleProvider<EncapsulationResolution> {
  _FixedConfigProvider({this.config});

  EncapsulationConfig? config;
  List<String> errors = const [];

  final PathMatcher matcher = GlobPathMatcher();
  final PackageConfigSource source = PackageConfigSource(
    ruleKey: encapsulationRuleName,
  );

  @override
  EncapsulationResolution? resolve(RuleContext context) =>
      EncapsulationResolution(
        config: config,
        matcher: matcher,
        source: source,
        errors: errors,
      );
}

EncapsulationConfig _config(
  List<Encapsulation> encapsulations, {
  RuleSeverity severity = RuleSeverity.info,
}) => EncapsulationConfig(
  version: 1,
  severity: severity,
  encapsulations: encapsulations,
);

Encapsulation _byFile({
  List<String> files = const ['lib/test.dart'],
  Map<String, bool> requirements = const {
    fieldsPrivateRequirement: true,
    privateFieldsFinalRequirement: true,
    noPublicSettersRequirement: true,
  },
  Map<String, RuleSeverity> severities = const {},
  RuleSeverity? severity,
}) => Encapsulation(
  files: files,
  requirements: requirements,
  severities: severities,
  severity: severity,
);

@reflectiveTest
class EncapsulationTest extends AnalysisRuleTest {
  late _FixedConfigProvider _provider;

  @override
  void setUp() {
    _provider = _FixedConfigProvider(config: _config([_byFile()]));
    rule = EncapsulationRule(provider: _provider);
    super.setUp();
  }

  Future<void> test_flags_public_field() async {
    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_flags_private_non_final_field() async {
    await assertDiagnostics(
      r'''
class HomeViewModel {
  String _title = '';
}
''',
      [lint(24, 19)],
    );
  }

  Future<void> test_flags_public_setter() async {
    await assertDiagnostics(
      r'''
class HomeViewModel {
  final String _v = '';
  set v(String value) {}
}
''',
      [lint(48, 22)],
    );
  }

  Future<void> test_flags_private_field_without_public_getter() async {
    _provider.config = _config([
      _byFile(requirements: const {requirePublicGettersRequirement: true}),
    ]);

    await assertDiagnostics(
      r'''
class HomeViewModel {
  final String _title = '';
}
''',
      [lint(24, 25)],
    );
  }

  Future<void> test_selects_by_supertype() async {
    _provider.config = _config([
      Encapsulation(
        selectors: const [SupertypeSelector('ChangeNotifier')],
        requirements: const {fieldsPrivateRequirement: true},
      ),
    ]);

    await assertDiagnostics(
      r'''
class ChangeNotifier {}
class MyViewModel extends ChangeNotifier {
  int count = 0;
}
''',
      [lint(69, 14)],
    );
  }

  Future<void> test_selects_by_file_glob() async {
    _provider.config = _config([
      _byFile(
        files: const ['lib/**'],
        requirements: const {fieldsPrivateRequirement: true},
      ),
    ]);

    await assertDiagnostics(
      r'''
class HomeViewModel {
  int count = 0;
}
''',
      [lint(24, 14)],
    );
  }

  Future<void> test_ignores_unselected_classes() async {
    _provider.config = _config([
      Encapsulation(
        selectors: const [NameEndsWithSelector('ViewModel')],
        requirements: const {fieldsPrivateRequirement: true},
      ),
    ]);

    await assertNoDiagnostics(r'''
class HomeScreen {
  int count = 0;
}
''');
  }

  Future<void> test_ignores_files_outside_the_glob() async {
    _provider.config = _config([
      _byFile(
        files: const ['lib/src/pages/**'],
        requirements: const {fieldsPrivateRequirement: true},
      ),
    ]);

    await assertNoDiagnostics(r'''
class HomeViewModel {
  int count = 0;
}
''');
  }

  Future<void> test_reports_config_errors() async {
    _provider.config = null;
    _provider.errors = ['boom'];

    await assertDiagnostics(
      r'''
class HomeViewModel {}
''',
      [lint(0, 0)],
    );
  }

  Future<void> test_ignore_comment_suppresses() async {
    await assertNoDiagnostics(r'''
class HomeViewModel {
  // ignore: encapsulation
  int count = 0;
}
''');
  }

  Future<void> test_ignore_comment_suppresses_error_severity() async {
    _provider.config = _config([
      _byFile(severity: RuleSeverity.error),
    ], severity: RuleSeverity.error);

    await assertNoDiagnostics(r'''
class HomeViewModel {
  // ignore: encapsulation
  int count = 0;
}
''');
  }

  void test_severity_codes() {
    expect(
      EncapsulationRule.codeFor(RuleSeverity.info).severity,
      DiagnosticSeverity.INFO,
    );
    expect(
      EncapsulationRule.codeFor(RuleSeverity.warning).severity,
      DiagnosticSeverity.WARNING,
    );
    expect(
      EncapsulationRule.codeFor(RuleSeverity.error).severity,
      DiagnosticSeverity.ERROR,
    );
    // All severities share the display name, so one ignore comment covers
    // every severity of the rule.
    expect(EncapsulationRule.infoCode.lowerCaseName, encapsulationRuleName);
    expect(EncapsulationRule.warningCode.lowerCaseName, encapsulationRuleName);
    expect(EncapsulationRule.errorCode.lowerCaseName, encapsulationRuleName);
  }
}
