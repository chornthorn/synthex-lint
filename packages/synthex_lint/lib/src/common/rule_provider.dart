import 'package:analyzer/analysis_rule/rule_context.dart';

/// Resolves what a rule needs for the library currently being analyzed.
///
/// This is the port every config-driven rule depends on instead of reaching for
/// the file system: the production implementations read the package
/// configuration through `PackageConfigSource`, while a rule's tests inject a
/// fixed resolution without a file system at all.
///
/// [Resolution] is the rule's own resolution type — `ArchitectureResolution`,
/// `EncapsulationResolution` — which carries the parsed configuration and any
/// configuration errors worth reporting.
abstract interface class RuleProvider<Resolution> {
  /// The resolution for this analysis, or `null` when the rule is not
  /// configured for this package and should stay inert.
  Resolution? resolve(RuleContext context);
}
