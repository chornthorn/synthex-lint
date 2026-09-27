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
import 'domain/encapsulation_evaluator.dart';
import 'infrastructure/encapsulation_resolution.dart';

/// Enforces that a class's state is private and changes only through methods.
///
/// The rule reads the `encapsulation` section of the plugin's config document —
/// `synthex_lint.yaml`, `.yml`, or `.json` in the analyzed package's root, or
/// the `synthex_lint` key of its `pubspec.yaml`, a dedicated file winning when
/// both are present. It stays inert until that section exists. Each configured
/// encapsulation selects the classes it governs — by file glob, by supertype,
/// class name, or annotation — and declares which requirements they must
/// satisfy, so the same conventions can be applied to view models, pages, or
/// any other family of classes.
///
/// `supertype` selection needs resolved elements, so enabling this rule turns
/// off the parsed-results fast path for the package.
class EncapsulationRule extends MultiAnalysisRule {
  /// Reported when the config does not request a different severity.
  static const LintCode infoCode = LintCode(encapsulationRuleName, '{0}');

  /// Reported for violations configured as `warning`.
  static const LintCode warningCode = LintCode(
    encapsulationRuleName,
    '{0}',
    uniqueName: 'LintCode.$encapsulationRuleName.warning',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Reported for violations configured as `error`, and for a broken config.
  static const LintCode errorCode = LintCode(
    encapsulationRuleName,
    '{0}',
    uniqueName: 'LintCode.$encapsulationRuleName.error',
    severity: DiagnosticSeverity.ERROR,
  );

  /// The diagnostic code for [severity].
  ///
  /// All three codes share the display name `encapsulation`, so a single
  /// `// ignore: encapsulation` comment suppresses the rule at every severity.
  static DiagnosticCode codeFor(RuleSeverity severity) => switch (severity) {
    RuleSeverity.info => infoCode,
    RuleSeverity.warning => warningCode,
    RuleSeverity.error => errorCode,
  };

  final RuleProvider<EncapsulationResolution> _provider;

  EncapsulationRule({RuleProvider<EncapsulationResolution>? provider})
    : _provider = provider ?? EncapsulationProvider(),
      super(
        name: encapsulationRuleName,
        description:
            'Enforces that state is private and changes only through methods.',
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
    final visitor = _EncapsulationVisitor(this, context, _provider);
    registry.addCompilationUnit(this, visitor);
    registry.addClassDeclaration(this, visitor);
  }
}

class _EncapsulationVisitor extends SimpleAstVisitor<void> {
  _EncapsulationVisitor(this.rule, this.context, this.provider);

  final EncapsulationRule rule;
  final RuleContext context;
  final RuleProvider<EncapsulationResolution> provider;

  /// The resolution is read once per analyzed unit — the config errors belong
  /// to the file, and re-parsing the config for every class would repeat work
  /// for nothing.
  EncapsulationResolution? _resolution;
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

    final facts = _classFacts(node);
    final evaluator = EncapsulationEvaluator(
      config: config,
      matcher: resolution.matcher,
    );
    final violations = evaluator.evaluateClass(path: filePath, facts: facts);
    if (violations.isEmpty) return;

    final nodeByMember = <String, AstNode>{};
    for (final member in node.body.members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          nodeByMember['field:${variable.name.lexeme}'] = member;
        }
      } else if (member is MethodDeclaration) {
        if (member.isGetter) {
          nodeByMember['getter:${member.name.lexeme}'] = member;
        } else if (member.isSetter) {
          nodeByMember['setter:${member.name.lexeme}'] = member;
        }
      }
    }

    for (final violation in violations) {
      final target =
          nodeByMember['${violation.member.kind.name}:${violation.member.name}'];
      final diagnosticCode = EncapsulationRule.codeFor(violation.severity);
      if (target != null) {
        rule.reportAtNode(
          target,
          diagnosticCode: diagnosticCode,
          arguments: [violation.message],
        );
      } else {
        // Defensive: report on the class declaration when the exact member
        // cannot be located (for example in an incomplete, mid-edit file).
        rule.reportAtNode(
          node,
          diagnosticCode: diagnosticCode,
          arguments: [violation.message],
        );
      }
    }
  }

  ClassFacts _classFacts(ClassDeclaration node) {
    final supertypeNames = <String>[
      for (final type
          in node.declaredFragment?.element.allSupertypes ??
              const <InterfaceType>[])
        ?type.element.name,
    ];
    final annotations = <String>[
      for (final annotation in node.metadata) annotation.name.name,
    ];

    final fields = <FieldFacts>[];
    final accessors = <AccessorFacts>[];
    for (final member in node.body.members) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          fields.add(
            FieldFacts(
              name: variable.name.lexeme,
              isStatic: member.isStatic,
              isFinal: member.fields.isFinal,
            ),
          );
        }
      } else if (member is MethodDeclaration) {
        if (member.isGetter) {
          accessors.add(
            AccessorFacts(
              name: member.name.lexeme,
              isGetter: true,
              isStatic: member.isStatic,
            ),
          );
        } else if (member.isSetter) {
          accessors.add(
            AccessorFacts(
              name: member.name.lexeme,
              isGetter: false,
              isStatic: member.isStatic,
            ),
          );
        }
      }
    }

    return ClassFacts(
      name: node.namePart.typeName.lexeme,
      supertypeNames: supertypeNames,
      annotations: annotations,
      fields: fields,
      accessors: accessors,
    );
  }

  EncapsulationResolution? _resolutionForUnit() {
    if (_isResolved) return _resolution;
    _isResolved = true;
    final resolution = provider.resolve(context);
    if (resolution == null) return null;
    reportConfigErrors(
      rule,
      resolution,
      diagnosticCode: EncapsulationRule.errorCode,
    );
    return _resolution = resolution;
  }
}
