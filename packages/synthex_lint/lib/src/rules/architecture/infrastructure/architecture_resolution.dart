import 'package:analyzer/analysis_rule/rule_context.dart';

import '../../../common/glob_path_matcher.dart';
import '../../../common/package_config_source.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_keys.dart';
import '../../../common/rule_provider.dart';
import '../../../common/rule_resolution.dart';
import '../domain/architecture_schema.dart';

/// The schema and package identity resolved for the current analysis.
///
/// The rule depends on `RuleProvider<ArchitectureResolution>`, so a test
/// injects a resolution without a file system and [ArchitectureProvider] is the
/// production implementation.
final class ArchitectureResolution extends RuleResolution {
  const ArchitectureResolution({
    this.schema,
    this.packageName,
    required super.matcher,
    required super.source,
    super.errors,
  });

  final ArchitectureSchema? schema;
  final String? packageName;
}

/// Reads the architecture schema from the analyzed package.
///
/// The section is the `architecture` key of the plugin configuration document
/// (`synthex_lint.yaml`, `.yml`, or `.json`), or of the `synthex_lint` key of
/// `pubspec.yaml`.
class ArchitectureProvider implements RuleProvider<ArchitectureResolution> {
  ArchitectureProvider({PathMatcher? matcher})
    : _matcher = matcher ?? GlobPathMatcher(),
      _config = PackageConfigSource(ruleKey: architectureRuleName);

  final PathMatcher _matcher;
  final PackageConfigSource _config;

  @override
  ArchitectureResolution? resolve(RuleContext context) {
    final document = _config.config(context);
    if (document == null) return null;
    final packageName = _config.packageName(context);
    if (document.error case final error?) {
      return ArchitectureResolution(
        matcher: _matcher,
        source: _config,
        packageName: packageName,
        errors: [error],
      );
    }
    final result = parseArchitectureSchema(
      document.document,
      matcher: _matcher,
    );
    return ArchitectureResolution(
      schema: result.schema,
      matcher: _matcher,
      source: _config,
      packageName: packageName,
      errors: [for (final error in result.errors) '${document.source}: $error'],
    );
  }
}
