import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../common/package_paths.dart';
import '../../common/rule_keys.dart';
import '../../common/rule_provider.dart';
import '../../common/rule_resolution.dart';
import '../../common/rule_severity.dart';
import 'domain/architecture_evaluator.dart';
import 'infrastructure/architecture_resolution.dart';

/// Enforces the layer structure declared in the plugin configuration.
///
/// The rule reads the `architecture` section of the plugin's config document —
/// `synthex_lint.yaml`, `.yml`, or `.json` in the analyzed package's root, or
/// the `synthex_lint` key of its `pubspec.yaml`, a dedicated file winning when
/// both are present. It stays inert until that section exists. See the package
/// README for the schema format. Severities are chosen per architectural rule
/// in the schema, so a violation can be reported as info, warning, or error.
class ArchitectureRule extends MultiAnalysisRule {
  /// Reported when the schema does not request a different severity.
  static const LintCode infoCode = LintCode(architectureRuleName, '{0}');

  /// Reported for violations configured as `warning`.
  static const LintCode warningCode = LintCode(
    architectureRuleName,
    '{0}',
    uniqueName: 'LintCode.$architectureRuleName.warning',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Reported for violations configured as `error`, and for a broken schema:
  /// an invalid configuration must not be silent.
  static const LintCode errorCode = LintCode(
    architectureRuleName,
    '{0}',
    uniqueName: 'LintCode.$architectureRuleName.error',
    severity: DiagnosticSeverity.ERROR,
  );

  /// The diagnostic code for [severity].
  ///
  /// All three codes share the display name `architecture`, so a single
  /// `// ignore: architecture` comment suppresses the rule at every severity.
  static DiagnosticCode codeFor(RuleSeverity severity) => switch (severity) {
    RuleSeverity.info => infoCode,
    RuleSeverity.warning => warningCode,
    RuleSeverity.error => errorCode,
  };

  final RuleProvider<ArchitectureResolution> _provider;

  /// Creates the rule with [provider], defaulting to `ArchitectureProvider`.
  ArchitectureRule({RuleProvider<ArchitectureResolution>? provider})
    : _provider = provider ?? ArchitectureProvider(),
      super(
        name: architectureRuleName,
        description:
            'Enforces layer boundaries declared in the architecture config.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    infoCode,
    warningCode,
    errorCode,
  ];

  /// The rule reads syntax and the package layout only — no elements, no
  /// types — so the plugin server can skip forcing full resolution for files
  /// where every enabled rule is syntax-only, and the rule still works while
  /// a file does not compile.
  @override
  bool get canUseParsedResult => true;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(
      this,
      _ArchitectureVisitor(this, context, _provider),
    );
  }
}

class _ArchitectureVisitor extends SimpleAstVisitor<void> {
  _ArchitectureVisitor(this.rule, this.context, this.provider);

  final ArchitectureRule rule;
  final RuleContext context;
  final RuleProvider<ArchitectureResolution> provider;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final resolution = provider.resolve(context);
    if (resolution == null) return;
    reportConfigErrors(
      rule,
      resolution,
      diagnosticCode: ArchitectureRule.errorCode,
    );

    final schema = resolution.schema;
    if (schema == null) return;

    final filePath = resolution.source.packageRelativePath(context);
    if (filePath == null) return;

    final imports = <ImportFacts>[];
    final directiveByUri = <String, AstNode>{};
    for (final directive in node.directives) {
      final StringLiteral uriLiteral;
      if (directive is ImportDirective) {
        uriLiteral = directive.uri;
      } else if (directive is ExportDirective) {
        uriLiteral = directive.uri;
      } else {
        continue;
      }
      final uri = uriLiteral.stringValue;
      if (uri == null || uri.isEmpty) continue;
      imports.add(
        ImportFacts(
          uri: uri,
          target: classifyImport(
            uri: uri,
            importingFilePath: filePath,
            packageName: resolution.packageName,
          ),
        ),
      );
      directiveByUri.putIfAbsent(uri, () => directive);
    }

    final evaluator = ArchitectureEvaluator(
      schema: schema,
      matcher: resolution.matcher,
    );
    final reported = <String>{};
    final violations = evaluator.evaluate(
      FileFacts(path: filePath, imports: imports),
    );
    for (final violation in violations) {
      // A URI can appear in more than one directive; report each distinct
      // violation once.
      if (!reported.add('${violation.uri}\u0000${violation.message}')) continue;
      final diagnosticCode = ArchitectureRule.codeFor(violation.severity);
      final directive = directiveByUri[violation.uri];
      if (directive != null) {
        rule.reportAtNode(
          directive,
          diagnosticCode: diagnosticCode,
          arguments: [violation.message],
        );
      } else {
        rule.reportAtOffset(
          0,
          0,
          diagnosticCode: diagnosticCode,
          arguments: [violation.message],
        );
      }
    }
  }
}
