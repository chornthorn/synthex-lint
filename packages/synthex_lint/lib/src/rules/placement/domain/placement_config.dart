import '../../../common/config_patterns.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';

/// The config format version understood by this package.
const int placementConfigVersion = 1;

/// A class name suffix a placement requires.
class RequiredSuffix {
  /// Creates a required [suffix], optionally exempting private classes.
  const RequiredSuffix({required this.suffix, this.excludesPrivate = false});

  /// The suffix a class name must end with.
  final String suffix;

  /// Whether private classes are exempt from this suffix.
  ///
  /// A `_Cache` in a `use_cases/` folder is an implementation detail, not part
  /// of the folder's vocabulary, so a placement can require the suffix of the
  /// classes it publishes and leave the private ones alone.
  final bool excludesPrivate;

  /// Whether this requirement applies to [className] at all.
  ///
  /// An exempt class is left to the placement's other suffixes: exempting a
  /// class from one of several suffixes does not exempt it from the rest.
  bool appliesTo(String className) =>
      !excludesPrivate || !className.startsWith('_');
}

/// The conventions for the classes declared in the files a placement governs.
class Placement {
  /// Creates a placement whose files match [files].
  const Placement({
    required this.files,
    this.exempt = const [],
    this.classesMustEndWith = const [],
    this.mustHaveSupertype = const [],
    this.mustNotHaveSupertype = const [],
    this.severity,
  });

  /// Package-relative glob patterns of the files this placement governs.
  final List<String> files;

  /// Patterns exempt from this placement, for example `**/*.g.dart`.
  final List<String> exempt;

  /// Required class name suffixes; empty means any name. A class must satisfy
  /// one of them.
  final List<RequiredSuffix> classesMustEndWith;

  /// Simple names of required supertypes — any of them; empty means any class.
  ///
  /// Matched against direct and indirect supertypes, interfaces, and mixins,
  /// the same set `supertype` selectors match in the `encapsulation` rule.
  final List<String> mustHaveSupertype;

  /// Simple names of forbidden supertypes.
  final List<String> mustNotHaveSupertype;

  /// Overrides the config-wide severity for this placement.
  final RuleSeverity? severity;

  /// The severity for violations of this placement.
  RuleSeverity severityFor(RuleSeverity configSeverity) =>
      severity ?? configSeverity;
}

/// A parsed placement configuration.
class PlacementConfig {
  /// Creates a config of [placements] at [version] with default [severity].
  const PlacementConfig({
    required this.version,
    required this.severity,
    required this.placements,
  });

  /// The config format version, currently [placementConfigVersion].
  final int version;

  /// Config-wide default severity for violations.
  final RuleSeverity severity;

  /// Placements in declaration order. Every placement whose `files` match a
  /// file constrains the classes declared in it.
  final List<Placement> placements;
}

/// The outcome of parsing a config document.
class PlacementConfigParseResult {
  /// Creates a result holding [config], or the validation [errors].
  const PlacementConfigParseResult({this.config, this.errors = const []});

  /// The parsed config, or `null` when [errors] is not empty.
  final PlacementConfig? config;

  /// Human-readable validation errors.
  final List<String> errors;

  /// Whether the document produced a config.
  bool get isValid => config != null;
}

const Set<String> _knownPlacementKeys = {
  'files',
  'exempt',
  'classesMustEndWith',
  'mustHaveSupertype',
  'mustNotHaveSupertype',
  'severity',
};

/// The keys a `classesMustEndWith` entry may hold.
const Set<String> _knownSuffixKeys = {'suffix', 'exclude'};

/// Parses `classesMustEndWith`: a suffix, a list of suffixes, or a list whose
/// entries pair a suffix with the classes it does not apply to.
///
/// ```yaml
/// classesMustEndWith:
///   - UseCase
///   - suffix: ViewModel
///     exclude: private
/// ```
List<RequiredSuffix>? _parseRequiredSuffixes(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  if (value == null) return null;
  final entries = value is List ? value : [value];
  if (entries.isEmpty) {
    errors.add("$where: 'classesMustEndWith' must not be empty.");
    return const [];
  }
  final suffixes = <RequiredSuffix>[];
  for (final entry in entries) {
    if (entry is String) {
      if (entry.isEmpty) {
        errors.add(
          "$where: 'classesMustEndWith' must hold non-empty suffixes.",
        );
        return const [];
      }
      suffixes.add(RequiredSuffix(suffix: entry));
      continue;
    }
    if (entry is! Map) {
      errors.add(
        "$where: 'classesMustEndWith' must hold suffixes, or maps with a "
        "'suffix' and an optional 'exclude'.",
      );
      return const [];
    }
    var hasUnknownKey = false;
    for (final key in entry.keys) {
      if (!_knownSuffixKeys.contains(key)) {
        hasUnknownKey = true;
        errors.add(
          "$where: unknown key '$key' in a classesMustEndWith entry "
          '(expected suffix or exclude).',
        );
      }
    }
    // An unknown key is reported as itself rather than also as a missing
    // suffix: a `subfix` typo already names what is wrong.
    if (hasUnknownKey) continue;
    final suffix = entry['suffix'];
    if (suffix is! String || suffix.isEmpty) {
      errors.add(
        "$where: a classesMustEndWith entry must declare a non-empty "
        "'suffix'.",
      );
      continue;
    }
    final exclude = entry['exclude'];
    if (exclude != null && exclude != 'private') {
      errors.add("$where: 'exclude' must be 'private', not '$exclude'.");
    }
    suffixes.add(
      RequiredSuffix(suffix: suffix, excludesPrivate: exclude == 'private'),
    );
  }
  return suffixes;
}

/// Parses and validates a decoded config document.
///
/// Every error is collected rather than failing fast, so a single run reports
/// everything that is wrong with the document.
PlacementConfigParseResult parsePlacementConfig(
  Object? document, {
  required PathMatcher matcher,
}) {
  if (document is! Map) {
    return const PlacementConfigParseResult(
      errors: ['The config must be a map.'],
    );
  }

  final errors = <String>[];

  final version = document['version'];
  if (version != null && version is! num ||
      version is num && version != placementConfigVersion) {
    errors.add(
      'Unsupported version: $version (expected $placementConfigVersion).',
    );
  }

  final severity =
      parseRuleSeverity(
        document['severity'],
        where: 'severity',
        errors: errors,
      ) ??
      RuleSeverity.info;

  final rawPlacements = document['placements'];
  if (rawPlacements is! List || rawPlacements.isEmpty) {
    errors.add("'placements' must be a non-empty list.");
    return PlacementConfigParseResult(errors: errors);
  }

  final placements = <Placement>[];
  for (var index = 0; index < rawPlacements.length; index++) {
    final raw = rawPlacements[index];
    final where = 'placements[$index]';
    if (raw is! Map) {
      errors.add('$where must be a map.');
      continue;
    }
    for (final key in raw.keys) {
      if (!_knownPlacementKeys.contains(key)) {
        errors.add(
          "$where: unknown key '$key' (expected files, exempt, "
          'classesMustEndWith, mustHaveSupertype, mustNotHaveSupertype, or '
          'severity).',
        );
      }
    }

    final files =
        parseConfigPatterns(
          raw['files'],
          where: where,
          field: 'files',
          matcher: matcher,
          errors: errors,
          isRequired: true,
        ) ??
        const [];
    final exempt =
        parseConfigPatterns(
          raw['exempt'],
          where: where,
          field: 'exempt',
          matcher: matcher,
          errors: errors,
        ) ??
        const [];
    final classesMustEndWith =
        _parseRequiredSuffixes(
          raw['classesMustEndWith'],
          where: where,
          errors: errors,
        ) ??
        const [];
    final mustHaveSupertype =
        parseConfigStrings(
          raw['mustHaveSupertype'],
          where: where,
          field: 'mustHaveSupertype',
          errors: errors,
        ) ??
        const [];
    final mustNotHaveSupertype =
        parseConfigStrings(
          raw['mustNotHaveSupertype'],
          where: where,
          field: 'mustNotHaveSupertype',
          errors: errors,
        ) ??
        const [];

    // Keyed off the raw document so a malformed check reports only its own
    // error, and a placement that declares no check at all reports this one.
    final declaresCheck =
        raw['classesMustEndWith'] != null ||
        raw['mustHaveSupertype'] != null ||
        raw['mustNotHaveSupertype'] != null;
    if (!declaresCheck) {
      errors.add(
        '$where must declare at least one of classesMustEndWith, '
        'mustHaveSupertype, or mustNotHaveSupertype.',
      );
    }

    placements.add(
      Placement(
        files: files,
        exempt: exempt,
        classesMustEndWith: classesMustEndWith,
        mustHaveSupertype: mustHaveSupertype,
        mustNotHaveSupertype: mustNotHaveSupertype,
        severity: parseRuleSeverity(
          raw['severity'],
          where: '$where.severity',
          errors: errors,
        ),
      ),
    );
  }

  if (errors.isNotEmpty) return PlacementConfigParseResult(errors: errors);
  return PlacementConfigParseResult(
    config: PlacementConfig(
      version: placementConfigVersion,
      severity: severity,
      placements: placements,
    ),
  );
}
