import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../../common/rule_keys.dart';
import '../../common/rule_provider.dart';
import '../../common/rule_resolution.dart';
import '../../common/rule_severity.dart';
import 'domain/placement_evaluator.dart';
import 'infrastructure/placement_resolution.dart';

/// Enforces where declarations live, and what they are named.
///
/// The rule reads the `placement` section of the plugin's config document —
/// `synthex_lint.yaml`, `.yml`, or `.json` in the analyzed package's root, or
/// the `synthex_lint` key of its `pubspec.yaml`, a dedicated file winning when
/// both are present. It stays inert until that section exists. Each configured
/// placement declares conventions for the classes declared in the files it
/// matches — the name suffix they must carry, the supertype they must have, or
/// the supertype they must not have — so a project can state "view models live
/// here and are named like this" once and have it enforced.
///
/// Matching supertypes needs resolved elements, so enabling this rule turns
/// off the parsed-results fast path for the package, as `encapsulation` does.
class PlacementRule extends MultiAnalysisRule {
  /// Reported when the config does not request a different severity.
  static const LintCode infoCode = LintCode(placementRuleName, '{0}');

  /// Reported for violations configured as `warning`.
  static const LintCode warningCode = LintCode(
    placementRuleName,
    '{0}',
    uniqueName: 'LintCode.$placementRuleName.warning',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Reported for violations configured as `error`, and for a broken config.
  static const LintCode errorCode = LintCode(
    placementRuleName,
    '{0}',
    uniqueName: 'LintCode.$placementRuleName.error',
    severity: DiagnosticSeverity.ERROR,
  );

  /// The diagnostic code for [severity].
  ///
  /// All three codes share the display name `placement`, so a single
  /// `// ignore: placement` comment suppresses the rule at every severity.
  static DiagnosticCode codeFor(RuleSeverity severity) => switch (severity) {
    RuleSeverity.info => infoCode,
    RuleSeverity.warning => warningCode,
    RuleSeverity.error => errorCode,
  };

  final RuleProvider<PlacementResolution> _provider;

  PlacementRule({RuleProvider<PlacementResolution>? provider})
    : _provider = provider ?? PlacementProvider(),
      super(
        name: placementRuleName,
        description:
            'Enforces where declarations live and what they are named.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    infoCode,
    warningCode,
    errorCode,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _PlacementVisitor(this, context, _provider);
    registry.addCompilationUnit(this, visitor);
    registry.addClassDeclaration(this, visitor);
  }
}

class _PlacementVisitor extends SimpleAstVisitor<void> {
  _PlacementVisitor(this.rule, this.context, this.provider);

  final PlacementRule rule;
  final RuleContext context;
  final RuleProvider<PlacementResolution> provider;

  /// The resolution is read once per analyzed unit — the config errors belong
  /// to the file, and re-parsing the config for every class would repeat work
  /// for nothing.
  PlacementResolution? _resolution;
  bool _isResolved = false;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Resolving here is what reports a broken configuration for this file.
    _resolutionForUnit();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final resolution = _resolutionForUnit();
    if (resolution == null) return;
    final config = resolution.config;
    final filePath = resolution.source.packageRelativePath(context);
    if (config == null || filePath == null) return;

    final facts = ClassFacts(
      name: node.namePart.typeName.lexeme,
      supertypeNames: [
        for (final type
            in node.declaredFragment?.element.allSupertypes ??
                const <InterfaceType>[])
          ?type.element.name,
      ],
    );
    final evaluator = PlacementEvaluator(
      config: config,
      matcher: resolution.matcher,
    );
    for (final violation in evaluator.evaluateClass(
      path: filePath,
      facts: facts,
    )) {
      rule.reportAtNode(
        node.namePart,
        diagnosticCode: PlacementRule.codeFor(violation.severity),
        arguments: [violation.message],
      );
    }
  }

  PlacementResolution? _resolutionForUnit() {
    if (_isResolved) return _resolution;
    _isResolved = true;
    final resolution = provider.resolve(context);
    if (resolution == null) return null;
    reportConfigErrors(
      rule,
      resolution,
      diagnosticCode: PlacementRule.errorCode,
    );
    return _resolution = resolution;
  }
}
