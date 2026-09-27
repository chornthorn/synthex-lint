import 'package:analyzer/analysis_rule/rule_context.dart';

import '../../../common/glob_path_matcher.dart';
import '../../../common/package_config_source.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_keys.dart';
import '../../../common/rule_provider.dart';
import '../../../common/rule_resolution.dart';
import '../domain/placement_config.dart';

/// The config resolved for the current analysis.
///
/// The rule depends on `RuleProvider<PlacementResolution>`, so a test injects a
/// resolution without a file system and [PlacementProvider] is the production
/// implementation.
class PlacementResolution extends RuleResolution {
  /// Creates the resolution for a package that configures the rule.
  const PlacementResolution({
    this.config,
    required super.matcher,
    required super.source,
    super.errors,
  });

  /// The parsed config, or `null` when the document could not be parsed.
  final PlacementConfig? config;
}

/// Reads the placement configuration from the analyzed package.
///
/// The section is the `placement` key of the plugin configuration document
/// (`synthex_lint.yaml`, `.yml`, or `.json`), or of the `synthex_lint` key of
/// `pubspec.yaml`.
class PlacementProvider implements RuleProvider<PlacementResolution> {
  /// Creates the provider with [matcher], defaulting to a `GlobPathMatcher`.
  PlacementProvider({PathMatcher? matcher})
    : _matcher = matcher ?? GlobPathMatcher(),
      _config = PackageConfigSource(ruleKey: placementRuleName);

  final PathMatcher _matcher;
  final PackageConfigSource _config;

  @override
  PlacementResolution? resolve(RuleContext context) {
    final document = _config.config(context);
    if (document == null) return null;
    if (document.error case final error?) {
      return PlacementResolution(
        matcher: _matcher,
        source: _config,
        errors: [error],
      );
    }
    final result = parsePlacementConfig(document.document, matcher: _matcher);
    if (result.isValid) {
      return PlacementResolution(
        config: result.config,
        matcher: _matcher,
        source: _config,
      );
    }
    return PlacementResolution(
      matcher: _matcher,
      source: _config,
      errors: [for (final error in result.errors) '${document.source}: $error'],
    );
  }
}
