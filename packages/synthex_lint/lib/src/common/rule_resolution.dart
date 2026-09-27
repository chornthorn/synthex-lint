import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';

import 'package_config_source.dart';
import 'path_matcher.dart';

/// Describes the result of resolving a rule for the currently analyzed file.
///
/// A resolution gives a rule everything it needs for that file:
/// - [source], the config loader the rule reads context facts from — the
///   analyzed file's package-relative path and the package name;
/// - [matcher], which configuration globs are matched with;
/// - the configuration that applies to the file, exposed by concrete subclasses
///   and typed for the rule (`ArchitectureResolution.schema`,
///   `EncapsulationResolution.config`);
/// - [errors] found while resolving, reportable with [reportConfigErrors].
///
/// Refer to [RuleProvider] for how a resolution is produced.
abstract class RuleResolution {
  /// Creates a resolution with [matcher], [source], and optional [errors].
  const RuleResolution({
    required this.matcher,
    required this.source,
    this.errors = const [],
  });

  /// The matcher that configuration globs are matched with.
  final PathMatcher matcher;

  /// The config loader the rule reads context facts from.
  final PackageConfigSource source;

  /// Validation errors for a broken configuration, prefixed with the source
  /// they come from; empty for a well-formed configuration.
  final List<String> errors;
}

/// Reports [resolution]'s configuration errors at the top of the analyzed file.
///
/// Deliberately loud: the analysis pipeline can run a rule several times per
/// file and discard earlier passes, so "report only once" bookkeeping gets
/// swallowed. A configuration error must not be silent, so it is reported on
/// every analyzed file.
void reportConfigErrors(
  MultiAnalysisRule rule,
  RuleResolution resolution, {
  required DiagnosticCode diagnosticCode,
}) {
  for (final error in resolution.errors) {
    rule.reportAtOffset(
      0,
      0,
      diagnosticCode: diagnosticCode,
      arguments: [error],
    );
  }
}
