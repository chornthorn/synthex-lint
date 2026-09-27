import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';

/// The config format version understood by this package.
const int architectureSchemaVersion = 1;

/// A declarative description of the architectural layers of a package.
class ArchitectureSchema {
  /// Creates a schema of [layers] at [version] with schema-wide [severity].
  const ArchitectureSchema({
    required this.version,
    this.severity = RuleSeverity.info,
    required this.layers,
  });

  /// The schema format version, currently [architectureSchemaVersion].
  final int version;

  /// Schema-wide default severity for violations.
  final RuleSeverity severity;

  /// Layers in declaration order. The first layer whose `files` pattern
  /// matches a path owns that path.
  final List<ArchitectureLayer> layers;
}

/// A forbidden URI pattern with an optional per-pattern severity.
class ForbiddenImport {
  /// Creates a forbidden import matching [pattern] with an optional
  /// [severity].
  const ForbiddenImport(this.pattern, {this.severity});

  /// A URI glob, matched against the import URI as written, for example
  /// `package:flutter/**` or `dart:io`.
  final String pattern;

  /// Overrides the layer severity for this pattern.
  final RuleSeverity? severity;
}

/// A single architecture layer.
class ArchitectureLayer {
  /// Creates a layer named [name] whose files match [files].
  const ArchitectureLayer({
    required this.name,
    required this.files,
    this.mayImport = const [],
    this.forbiddenImports = const [],
    this.severity,
    this.mayImportSeverity,
    this.forbiddenImportSeverity,
  });

  /// The layer name, referenced by [mayImport] of other layers.
  final String name;

  /// Package-relative glob patterns of this layer's files, for example
  /// `lib/src/domain/**`.
  final List<String> files;

  /// Names of other layers this layer is allowed to import. Importing any
  /// other layer is a violation.
  final List<String> mayImport;

  /// URI patterns this layer must never import.
  final List<ForbiddenImport> forbiddenImports;

  /// Default severity for violations in this layer; falls back to the schema
  /// severity.
  final RuleSeverity? severity;

  /// Overrides [severity] for layer-boundary violations.
  final RuleSeverity? mayImportSeverity;

  /// Overrides [severity] for forbidden-import violations that do not carry
  /// their own severity.
  final RuleSeverity? forbiddenImportSeverity;

  /// The severity for boundary violations.
  RuleSeverity boundarySeverity(RuleSeverity schemaSeverity) =>
      mayImportSeverity ?? severity ?? schemaSeverity;

  /// The severity for a forbidden-import violation.
  RuleSeverity forbiddenSeverity(
    ForbiddenImport forbidden,
    RuleSeverity schemaSeverity,
  ) =>
      forbidden.severity ??
      forbiddenImportSeverity ??
      severity ??
      schemaSeverity;
}

/// The outcome of parsing a schema document.
class ArchitectureSchemaParseResult {
  /// Creates a result holding [schema], or the validation [errors].
  const ArchitectureSchemaParseResult({this.schema, this.errors = const []});

  /// The parsed schema, or `null` when [errors] is not empty.
  final ArchitectureSchema? schema;

  /// Human-readable validation errors.
  final List<String> errors;

  /// Whether the document produced a schema.
  bool get isValid => schema != null;
}

/// Parses and validates a decoded schema document.
///
/// Every error is collected rather than failing fast, so a single run reports
/// everything that is wrong with the document.
ArchitectureSchemaParseResult parseArchitectureSchema(
  Object? document, {
  required PathMatcher matcher,
}) {
  if (document is! Map) {
    return const ArchitectureSchemaParseResult(
      errors: ['The schema must be a map.'],
    );
  }

  final errors = <String>[];

  final version = document['version'];
  if (version != null && version is! num ||
      version is num && version != architectureSchemaVersion) {
    errors.add(
      "Unsupported version: $version (expected $architectureSchemaVersion).",
    );
  }

  final schemaSeverity =
      _severityFrom(document['severity'], where: 'severity', errors: errors) ??
      RuleSeverity.info;

  final rawLayers = document['layers'];
  if (rawLayers is! List || rawLayers.isEmpty) {
    errors.add("'layers' must be a non-empty list.");
    return ArchitectureSchemaParseResult(errors: errors);
  }

  final layers = <ArchitectureLayer>[];
  final names = <String>{};
  for (var index = 0; index < rawLayers.length; index++) {
    final raw = rawLayers[index];
    final where = 'layers[$index]';
    if (raw is! Map) {
      errors.add('$where must be an object.');
      continue;
    }
    final name = raw['name'];
    if (name is! String || name.isEmpty) {
      errors.add("$where is missing a non-empty 'name'.");
      continue;
    }
    if (!names.add(name)) {
      errors.add("Duplicate layer name '$name'.");
      continue;
    }

    final files = _stringList(
      raw['files'],
      where: where,
      field: 'files',
      errors: errors,
      isRequired: true,
    );
    final mayImport = _stringList(
      raw['mayImport'],
      where: where,
      field: 'mayImport',
      errors: errors,
    );
    final forbiddenImports = _forbiddenImports(
      raw['forbiddenImports'],
      where: where,
      errors: errors,
    );
    final severities = _layerSeverities(
      raw['severity'],
      where: where,
      errors: errors,
    );

    for (final pattern in [
      ...files,
      ...forbiddenImports.map((forbidden) => forbidden.pattern),
    ]) {
      if (pattern.startsWith('/')) {
        errors.add(
          "$where: pattern '$pattern' must be relative to the package root.",
        );
        continue;
      }
      final patternError = matcher.validate(pattern);
      if (patternError != null) {
        errors.add("$where: invalid pattern '$pattern': $patternError");
      }
    }

    layers.add(
      ArchitectureLayer(
        name: name,
        files: files,
        mayImport: mayImport,
        forbiddenImports: forbiddenImports,
        severity: severities.defaultSeverity,
        mayImportSeverity: severities.mayImportSeverity,
        forbiddenImportSeverity: severities.forbiddenImportSeverity,
      ),
    );
  }

  for (final layer in layers) {
    for (final name in layer.mayImport) {
      if (!names.contains(name)) {
        errors.add("Layer '${layer.name}' may import unknown layer '$name'.");
      }
    }
  }

  if (errors.isNotEmpty) {
    return ArchitectureSchemaParseResult(errors: errors);
  }
  return ArchitectureSchemaParseResult(
    schema: ArchitectureSchema(
      version: architectureSchemaVersion,
      severity: schemaSeverity,
      layers: layers,
    ),
  );
}

/// The three severity slots a layer can declare.
class _LayerSeverities {
  const _LayerSeverities({
    this.defaultSeverity,
    this.mayImportSeverity,
    this.forbiddenImportSeverity,
  });

  final RuleSeverity? defaultSeverity;
  final RuleSeverity? mayImportSeverity;
  final RuleSeverity? forbiddenImportSeverity;
}

/// Parses a layer's `severity` field: either a single severity string, or an
/// object with `default`, `mayImport`, and `forbiddenImports` keys.
_LayerSeverities _layerSeverities(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  if (value == null) return const _LayerSeverities();
  if (value is String) {
    return _LayerSeverities(
      defaultSeverity: _severityFrom(
        value,
        where: '$where.severity',
        errors: errors,
      ),
    );
  }
  if (value is Map) {
    const knownKeys = {'default', 'mayImport', 'forbiddenImports'};
    for (final key in value.keys) {
      if (!knownKeys.contains(key)) {
        errors.add(
          "$where.severity: unknown key '$key' "
          "(expected default, mayImport, or forbiddenImports).",
        );
      }
    }
    return _LayerSeverities(
      defaultSeverity: _severityFrom(
        value['default'],
        where: "$where.severity.default",
        errors: errors,
      ),
      mayImportSeverity: _severityFrom(
        value['mayImport'],
        where: "$where.severity.mayImport",
        errors: errors,
      ),
      forbiddenImportSeverity: _severityFrom(
        value['forbiddenImports'],
        where: "$where.severity.forbiddenImports",
        errors: errors,
      ),
    );
  }
  errors.add(
    "$where.severity must be a severity string or an object with "
    "'default', 'mayImport', and 'forbiddenImports'.",
  );
  return const _LayerSeverities();
}

/// Parses a `forbiddenImports` list: entries are either a URI pattern string
/// or an object `{ "uri": ..., "severity": ... }`.
List<ForbiddenImport> _forbiddenImports(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  if (value == null) return const [];
  if (value is! List) {
    errors.add("$where: 'forbiddenImports' must be a list.");
    return const [];
  }
  final result = <ForbiddenImport>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    final entryWhere = '$where.forbiddenImports[$index]';
    if (entry is String && entry.isNotEmpty) {
      result.add(ForbiddenImport(entry));
      continue;
    }
    if (entry is Map) {
      for (final key in entry.keys) {
        if (key != 'uri' && key != 'severity') {
          errors.add(
            "$entryWhere: unknown key '$key' (expected uri or severity).",
          );
        }
      }
      final uri = entry['uri'];
      if (uri is! String || uri.isEmpty) {
        errors.add("$entryWhere: 'uri' must be a non-empty string.");
        continue;
      }
      result.add(
        ForbiddenImport(
          uri,
          severity: _severityFrom(
            entry['severity'],
            where: '$entryWhere.severity',
            errors: errors,
          ),
        ),
      );
      continue;
    }
    errors.add(
      "$entryWhere must be a URI pattern string or an object with 'uri'.",
    );
  }
  return result;
}

RuleSeverity? _severityFrom(
  Object? value, {
  required String where,
  required List<String> errors,
}) => parseRuleSeverity(value, where: where, errors: errors);

List<String> _stringList(
  Object? value, {
  required String where,
  required String field,
  required List<String> errors,
  bool isRequired = false,
}) {
  if (value == null) {
    if (isRequired) errors.add("$where: '$field' is required.");
    return const [];
  }
  if (value is! List) {
    errors.add("$where: '$field' must be a list of strings.");
    return const [];
  }
  final result = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.isEmpty) {
      errors.add("$where: '$field' must contain non-empty strings.");
      return const [];
    }
    result.add(entry);
  }
  if (isRequired && result.isEmpty) {
    errors.add("$where: '$field' must not be empty.");
  }
  return result;
}
