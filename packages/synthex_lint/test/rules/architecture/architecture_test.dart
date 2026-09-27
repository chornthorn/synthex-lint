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
import 'package:synthex_lint/src/rules/architecture/architecture_rule.dart';
import 'package:synthex_lint/src/rules/architecture/domain/architecture_schema.dart';
import 'package:synthex_lint/src/rules/architecture/infrastructure/architecture_resolution.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ArchitectureTest);
  });
}

/// Injects a fixed schema so rule tests do not need a file system.
///
/// The resolution still carries the real matcher and config source, so the
/// analyzed file's path comes from the analysis context as it does in
/// production.
class _FixedSchemaProvider implements RuleProvider<ArchitectureResolution> {
  _FixedSchemaProvider({this.schema});

  ArchitectureSchema? schema;
  String packageName = 'test';
  List<String> errors = const [];

  final PathMatcher matcher = GlobPathMatcher();
  final PackageConfigSource source = PackageConfigSource(
    ruleKey: architectureRuleName,
  );

  @override
  ArchitectureResolution? resolve(RuleContext context) =>
      ArchitectureResolution(
        schema: schema,
        packageName: packageName,
        matcher: matcher,
        source: source,
        errors: errors,
      );
}

ArchitectureSchema _twoLayerSchema({List<String> mayImport = const []}) =>
    ArchitectureSchema(
      version: 1,
      layers: [
        ArchitectureLayer(
          name: 'presentation',
          files: ['lib/test.dart'],
          mayImport: mayImport,
        ),
        ArchitectureLayer(name: 'data', files: ['lib/src/data/**']),
      ],
    );

@reflectiveTest
class ArchitectureTest extends AnalysisRuleTest {
  late _FixedSchemaProvider _provider;

  @override
  void setUp() {
    _provider = _FixedSchemaProvider(schema: _twoLayerSchema());
    rule = ArchitectureRule(provider: _provider);
    super.setUp();
  }

  Future<void> test_flags_layer_export() async {
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    await assertDiagnostics(
      r'''
export 'package:test/src/data/repo.dart';
''',
      [lint(0, 41)],
    );
  }

  Future<void> test_allows_declared_layer_export() async {
    _provider.schema = _twoLayerSchema(mayImport: ['data']);
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    await assertNoDiagnostics(r'''
export 'package:test/src/data/repo.dart';
''');
  }

  Future<void> test_flags_forbidden_uri() async {
    _provider.schema = ArchitectureSchema(
      version: 1,
      layers: [
        ArchitectureLayer(
          name: 'presentation',
          files: ['lib/test.dart'],
          forbiddenImports: [ForbiddenImport('dart:io')],
        ),
      ],
    );
    await assertDiagnostics(
      r'''
export 'dart:io';
''',
      [lint(0, 17)],
    );
  }

  Future<void> test_ignores_files_outside_layers() async {
    _provider.schema = ArchitectureSchema(
      version: 1,
      layers: [
        ArchitectureLayer(name: 'domain', files: ['lib/src/domain/**']),
      ],
    );
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    await assertNoDiagnostics(r'''
export 'package:test/src/data/repo.dart';
''');
  }

  Future<void> test_reports_schema_errors() async {
    _provider.schema = null;
    _provider.errors = ['boom'];
    await assertDiagnostics(
      r'''
export 'dart:io';
''',
      [lint(0, 0)],
    );
  }

  Future<void> test_ignore_comment_suppresses() async {
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    await assertNoDiagnostics(r'''
// ignore: architecture
export 'package:test/src/data/repo.dart';
''');
  }

  void test_severity_codes() {
    expect(
      ArchitectureRule.codeFor(RuleSeverity.info).severity,
      DiagnosticSeverity.INFO,
    );
    expect(
      ArchitectureRule.codeFor(RuleSeverity.warning).severity,
      DiagnosticSeverity.WARNING,
    );
    expect(
      ArchitectureRule.codeFor(RuleSeverity.error).severity,
      DiagnosticSeverity.ERROR,
    );
    // All severities share the display name, so one ignore comment covers
    // every severity of the rule.
    expect(ArchitectureRule.infoCode.lowerCaseName, architectureRuleName);
    expect(ArchitectureRule.warningCode.lowerCaseName, architectureRuleName);
    expect(ArchitectureRule.errorCode.lowerCaseName, architectureRuleName);
  }

  Future<void> test_ignore_comment_suppresses_error_severity() async {
    _provider.schema = ArchitectureSchema(
      version: 1,
      severity: RuleSeverity.error,
      layers: [
        ArchitectureLayer(name: 'presentation', files: ['lib/test.dart']),
        ArchitectureLayer(name: 'data', files: ['lib/src/data/**']),
      ],
    );
    newFile('/home/test/lib/src/data/repo.dart', 'class Repo {}');
    await assertNoDiagnostics(r'''
// ignore: architecture
export 'package:test/src/data/repo.dart';
''');
  }
}
