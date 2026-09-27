import '../../../common/package_paths.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';
import 'architecture_schema.dart';

/// A single architecture violation found in a file.
class ArchitectureViolation {
  /// Creates a violation of [uri] with its diagnostic [message] and
  /// [severity].
  const ArchitectureViolation({
    required this.uri,
    required this.message,
    required this.severity,
  });

  /// The offending import URI, used to locate the directive to report on.
  final String uri;

  /// A human-readable description, used as the diagnostic message.
  final String message;

  /// The severity configured for this violation.
  final RuleSeverity severity;

  @override
  String toString() => message;
}

/// An import (or export) directive of the analyzed file.
class ImportFacts {
  /// Creates facts about an import of [uri] classified as [target].
  const ImportFacts({required this.uri, required this.target});

  /// The import URI as written in the directive.
  final String uri;

  /// Where [uri] points, classified relative to the analyzed package.
  final ImportTarget target;
}

/// The facts about the analyzed file that architecture rules depend on.
class FileFacts {
  /// Creates the facts for the file at [path] with its [imports].
  const FileFacts({required this.path, required this.imports});

  /// Package-relative POSIX path, for example `lib/src/domain/entity.dart`.
  final String path;

  /// The import and export directives of the file, in declaration order.
  final List<ImportFacts> imports;
}

/// Evaluates a [FileFacts] against an [ArchitectureSchema].
///
/// Pure: no analyzer, no file system, no state.
class ArchitectureEvaluator {
  /// Creates an evaluator for [schema] that matches paths with [matcher].
  const ArchitectureEvaluator({required this.schema, required this.matcher});

  /// The schema to evaluate against.
  final ArchitectureSchema schema;

  /// The matcher that layer `files` patterns are matched with.
  final PathMatcher matcher;

  /// The first layer whose `files` patterns match [packageRelativePath], or
  /// `null` when no layer owns the path.
  ArchitectureLayer? layerForPath(String packageRelativePath) {
    for (final layer in schema.layers) {
      for (final pattern in layer.files) {
        if (matcher.matches(pattern, packageRelativePath)) return layer;
      }
    }
    return null;
  }

  /// All violations for [file], in declaration order of its imports.
  List<ArchitectureViolation> evaluate(FileFacts file) {
    final ownLayer = layerForPath(file.path);
    if (ownLayer == null) return const [];

    final violations = <ArchitectureViolation>[];
    for (final import in file.imports) {
      final target = import.target;
      if (target is InternalImport) {
        final targetLayer = layerForPath(target.path);
        if (targetLayer != null &&
            targetLayer.name != ownLayer.name &&
            !ownLayer.mayImport.contains(targetLayer.name)) {
          violations.add(
            ArchitectureViolation(
              uri: import.uri,
              severity: ownLayer.boundarySeverity(schema.severity),
              message:
                  "Layer '${ownLayer.name}' may not import '${targetLayer.name}' "
                  "(import '${import.uri}').",
            ),
          );
        }
      }
      for (final forbidden in ownLayer.forbiddenImports) {
        if (matcher.matches(forbidden.pattern, import.uri)) {
          violations.add(
            ArchitectureViolation(
              uri: import.uri,
              severity: ownLayer.forbiddenSeverity(forbidden, schema.severity),
              message:
                  "Layer '${ownLayer.name}' forbids import '${import.uri}'.",
            ),
          );
        }
      }
    }
    return violations;
  }
}
