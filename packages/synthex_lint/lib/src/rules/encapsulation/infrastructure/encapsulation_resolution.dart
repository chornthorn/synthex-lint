import 'package:analyzer/analysis_rule/rule_context.dart';

import '../../../common/glob_path_matcher.dart';
import '../../../common/package_config_source.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_keys.dart';
import '../../../common/rule_provider.dart';
import '../../../common/rule_resolution.dart';
import '../domain/encapsulation_config.dart';

/// The config resolved for the current analysis.
///
/// The rule depends on `RuleProvider<EncapsulationResolution>`, so a test
/// injects a resolution without a file system and [EncapsulationProvider] is
/// the production implementation.
class EncapsulationResolution extends RuleResolution {
  const EncapsulationResolution({
    this.config,
    required super.matcher,
    required super.source,
    super.errors,
  });

  final EncapsulationConfig? config;
}

/// Reads the encapsulation configuration from the analyzed package.
///
/// The section is the `encapsulation` key of the plugin configuration document
/// (`synthex_lint.yaml`, `.yml`, or `.json`), or of the `synthex_lint` key of
/// `pubspec.yaml`.
class EncapsulationProvider implements RuleProvider<EncapsulationResolution> {
  EncapsulationProvider({PathMatcher? matcher})
    : _matcher = matcher ?? GlobPathMatcher(),
      _config = PackageConfigSource(ruleKey: encapsulationRuleName);

  final PathMatcher _matcher;
  final PackageConfigSource _config;

  @override
  EncapsulationResolution? resolve(RuleContext context) {
    final document = _config.config(context);
    if (document == null) return null;
    if (document.error case final error?) {
      return EncapsulationResolution(
        matcher: _matcher,
        source: _config,
        errors: [error],
      );
    }
    final result = parseEncapsulationConfig(
      document.document,
      matcher: _matcher,
    );
    if (result.isValid) {
      return EncapsulationResolution(
        config: result.config,
        matcher: _matcher,
        source: _config,
      );
    }
    return EncapsulationResolution(
      matcher: _matcher,
      source: _config,
      errors: [for (final error in result.errors) '${document.source}: $error'],
    );
  }
}
