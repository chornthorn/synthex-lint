import '../../../common/config_patterns.dart';
import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';

/// The config format version understood by this package.
const int encapsulationConfigVersion = 1;

/// Instance fields must be private.
const String fieldsPrivateRequirement = 'fieldsPrivate';

/// Private instance fields must be `final`.
const String privateFieldsFinalRequirement = 'privateFieldsFinal';

/// Setters must not be public.
const String noPublicSettersRequirement = 'noPublicSetters';

/// Every private instance field must be exposed by a public getter.
const String requirePublicGettersRequirement = 'requirePublicGetters';

/// All requirement names, as accepted in the config.
const List<String> encapsulationRequirementNames = [
  fieldsPrivateRequirement,
  privateFieldsFinalRequirement,
  noPublicSettersRequirement,
  requirePublicGettersRequirement,
];

/// Defaults applied when `requirements` omits an entry.
const Map<String, bool> _defaultRequirements = {
  fieldsPrivateRequirement: true,
  privateFieldsFinalRequirement: true,
  noPublicSettersRequirement: true,
  requirePublicGettersRequirement: false,
};

/// A selector for the classes an encapsulation applies to.
///
/// Selection by path is expressed with `files`, which takes globs.
sealed class ClassSelector {
  const ClassSelector();
}

/// Matches classes that have [name] among their supertypes, interfaces, or
/// mixins — direct or indirect. Needs resolved elements.
final class SupertypeSelector extends ClassSelector {
  const SupertypeSelector(this.name);

  final String name;
}

/// Matches classes whose name ends with [suffix].
final class NameEndsWithSelector extends ClassSelector {
  const NameEndsWithSelector(this.suffix);

  final String suffix;
}

/// Matches classes whose name starts with [prefix].
final class NameStartsWithSelector extends ClassSelector {
  const NameStartsWithSelector(this.prefix);

  final String prefix;
}

/// Matches classes annotated with the annotation called [name].
final class AnnotationSelector extends ClassSelector {
  const AnnotationSelector(this.name);

  final String name;
}

/// The conventions for the classes an encapsulation selects.
class Encapsulation {
  const Encapsulation({
    this.files = const [],
    this.selectors = const [],
    this.requirements = _defaultRequirements,
    this.severities = const {},
    this.severity,
  });

  /// Package-relative glob patterns of the files this encapsulation governs.
  final List<String> files;

  /// Element-based selectors; a class is checked when its path matches any
  /// [files] pattern or any selector matches.
  final List<ClassSelector> selectors;

  /// Resolved requirement flags, one entry per [encapsulationRequirementNames].
  final Map<String, bool> requirements;

  /// Per-requirement severity overrides.
  final Map<String, RuleSeverity> severities;

  /// Overrides the config-wide severity for this encapsulation.
  final RuleSeverity? severity;

  bool isEnabled(String requirement) => requirements[requirement] ?? false;

  /// The severity for [requirement]: the most specific setting wins.
  RuleSeverity severityFor(String requirement, RuleSeverity configSeverity) =>
      severities[requirement] ?? severity ?? configSeverity;
}

/// A parsed encapsulation configuration.
class EncapsulationConfig {
  const EncapsulationConfig({
    required this.version,
    required this.severity,
    required this.encapsulations,
  });

  final int version;

  /// Config-wide default severity for violations.
  final RuleSeverity severity;

  /// Encapsulations in declaration order. Every one that selects a class
  /// constrains it.
  final List<Encapsulation> encapsulations;
}

/// The outcome of parsing a config document.
class EncapsulationConfigParseResult {
  const EncapsulationConfigParseResult({this.config, this.errors = const []});

  /// The parsed config, or `null` when [errors] is not empty.
  final EncapsulationConfig? config;

  /// Human-readable validation errors.
  final List<String> errors;

  bool get isValid => config != null;
}

const Set<String> _knownEncapsulationKeys = {
  'files',
  'selectors',
  'requirements',
  'severities',
  'severity',
};

/// Parses and validates a decoded config document.
///
/// Every error is collected rather than failing fast, so a single run reports
/// everything that is wrong with the document.
EncapsulationConfigParseResult parseEncapsulationConfig(
  Object? document, {
  required PathMatcher matcher,
}) {
  if (document is! Map) {
    return const EncapsulationConfigParseResult(
      errors: ['The config must be a map.'],
    );
  }

  final errors = <String>[];

  final version = document['version'];
  if (version != null && version is! num ||
      version is num && version != encapsulationConfigVersion) {
    errors.add(
      'Unsupported version: $version (expected $encapsulationConfigVersion).',
    );
  }

  final severity =
      parseRuleSeverity(
        document['severity'],
        where: 'severity',
        errors: errors,
      ) ??
      RuleSeverity.info;

  final rawEncapsulations = document['encapsulations'];
  if (rawEncapsulations is! List || rawEncapsulations.isEmpty) {
    errors.add("'encapsulations' must be a non-empty list.");
    return EncapsulationConfigParseResult(errors: errors);
  }

  final encapsulations = <Encapsulation>[];
  for (var index = 0; index < rawEncapsulations.length; index++) {
    final raw = rawEncapsulations[index];
    final where = 'encapsulations[$index]';
    if (raw is! Map) {
      errors.add('$where must be a map.');
      continue;
    }
    for (final key in raw.keys) {
      if (!_knownEncapsulationKeys.contains(key)) {
        errors.add(
          "$where: unknown key '$key' (expected files, selectors, "
          'requirements, severities, or severity).',
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
        ) ??
        const [];
    final selectors = _selectors(
      raw['selectors'],
      where: where,
      errors: errors,
    );

    // Keyed off the raw document so a malformed selector list reports only its
    // own error, and an encapsulation that selects nothing at all reports this
    // one.
    final declaresSelection = raw['files'] != null || raw['selectors'] != null;
    if (!declaresSelection) {
      errors.add("$where must select classes with 'files' or 'selectors'.");
    }

    final settings = _requirementSettings(
      raw['requirements'],
      where: where,
      errors: errors,
    );

    encapsulations.add(
      Encapsulation(
        files: files,
        selectors: selectors,
        requirements: settings.requirements,
        // A requirement's own `severity` sits next to its `enabled` flag, so it
        // wins over the separate `severities` map when both name it.
        severities: {
          ..._severities(raw['severities'], where: where, errors: errors),
          ...settings.severities,
        },
        severity: parseRuleSeverity(
          raw['severity'],
          where: '$where.severity',
          errors: errors,
        ),
      ),
    );
  }

  if (errors.isNotEmpty) return EncapsulationConfigParseResult(errors: errors);
  return EncapsulationConfigParseResult(
    config: EncapsulationConfig(
      version: encapsulationConfigVersion,
      severity: severity,
      encapsulations: encapsulations,
    ),
  );
}

/// The requirement flags and per-requirement severities of one encapsulation.
typedef _RequirementSettings = ({
  Map<String, bool> requirements,
  Map<String, RuleSeverity> severities,
});

/// Parses `requirements`: a map of names to booleans, or a list whose entries
/// name one requirement each and may carry its settings.
///
/// ```yaml
/// requirements:
///   - fieldsPrivate:
///       enabled: true
///       severity: warning
///   - privateFieldsFinal: false
/// ```
_RequirementSettings _requirementSettings(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  final reader = _RequirementReader(where: where, errors: errors);
  reader.read(value);
  if (!reader.enabled.values.any((isEnabled) => isEnabled)) {
    errors.add('$where: at least one requirement must be enabled.');
  }
  return (requirements: reader.enabled, severities: reader.severities);
}

/// Reads the `requirements` value into the flags and severities it declares.
class _RequirementReader {
  _RequirementReader({required this.where, required this.errors});

  final String where;
  final List<String> errors;

  /// Requirement flags, starting from the defaults an omitted entry keeps.
  final Map<String, bool> enabled = Map<String, bool>.from(
    _defaultRequirements,
  );

  /// Severities named by a requirement entry.
  final Map<String, RuleSeverity> severities = {};

  void read(Object? value) {
    switch (value) {
      case null:
        return;
      case Map():
        _readMap(value);
      case List():
        for (var index = 0; index < value.length; index++) {
          _readEntry(value[index], index);
        }
      default:
        errors.add(
          "$where: 'requirements' must be a map of requirement names to "
          'booleans, or a list of requirement entries.',
        );
    }
  }

  void _readMap(Map<Object?, Object?> value) {
    for (final entry in value.entries) {
      final name = entry.key;
      if (!_isRequirement(name)) {
        errors.add(
          "$where: unknown requirement '$name' "
          '(expected ${encapsulationRequirementNames.join(', ')}).',
        );
        continue;
      }
      if (entry.value is! bool) {
        errors.add("$where: requirement '$name' must be true or false.");
        continue;
      }
      enabled[name as String] = entry.value as bool;
    }
  }

  void _readEntry(Object? entry, int index) {
    final entryWhere = '$where.requirements[$index]';
    if (entry is! Map) {
      errors.add('$entryWhere must name one requirement.');
      return;
    }
    final named = [
      for (final key in entry.keys)
        if (_isRequirement(key)) key as String,
    ];
    // `fieldsPrivate:` with `enabled` beside it is what a YAML indentation slip
    // produces; the settings belong under the name.
    if (named.length == 1 &&
        entry[named.single] == null &&
        (entry.containsKey('enabled') || entry.containsKey('severity'))) {
      errors.add(
        "$entryWhere: put 'enabled' and 'severity' under '${named.single}' — "
        "'${named.single}: {enabled: true, severity: warning}' — or write "
        "'${named.single}: true'.",
      );
      return;
    }
    if (named.length != 1) {
      errors.add(
        '$entryWhere must name exactly one requirement '
        '(${encapsulationRequirementNames.join(', ')}).',
      );
      return;
    }
    final name = named.single;
    switch (entry[name]) {
      case final bool flag:
        enabled[name] = flag;
      case final Map<Object?, Object?> settings:
        _readSettings(settings, name: name, entryWhere: entryWhere);
      default:
        errors.add(
          "$entryWhere: '$name' must be true, false, or a map with 'enabled' "
          "and 'severity'.",
        );
    }
  }

  void _readSettings(
    Map<Object?, Object?> settings, {
    required String name,
    required String entryWhere,
  }) {
    for (final key in settings.keys) {
      if (key != 'enabled' && key != 'severity') {
        errors.add(
          "$entryWhere: unknown key '$key' (expected enabled or severity).",
        );
      }
    }
    final flag = settings['enabled'];
    if (flag != null) {
      if (flag is bool) {
        enabled[name] = flag;
      } else {
        errors.add("$entryWhere: 'enabled' must be true or false.");
      }
    }
    final severity = parseRuleSeverity(
      settings['severity'],
      where: '$entryWhere.severity',
      errors: errors,
    );
    if (severity != null) severities[name] = severity;
  }

  bool _isRequirement(Object? key) =>
      key is String && encapsulationRequirementNames.contains(key);
}

Map<String, RuleSeverity> _severities(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  final severities = <String, RuleSeverity>{};
  if (value == null) return severities;
  if (value is! Map) {
    errors.add(
      "$where: 'severities' must be a map of requirement names to severities.",
    );
    return severities;
  }
  for (final entry in value.entries) {
    final name = entry.key;
    if (name is! String || !encapsulationRequirementNames.contains(name)) {
      errors.add("$where: unknown requirement in 'severities': '$name'.");
      continue;
    }
    final parsed = parseRuleSeverity(
      entry.value,
      where: '$where.severities.$name',
      errors: errors,
    );
    if (parsed != null) severities[name] = parsed;
  }
  return severities;
}

List<ClassSelector> _selectors(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  if (value == null) return const [];
  if (value is! List || value.isEmpty) {
    errors.add("$where: 'selectors' must be a non-empty list.");
    return const [];
  }
  final selectors = <ClassSelector>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    final entryWhere = '$where.selectors[$index]';
    if (entry is! Map) {
      errors.add('$entryWhere must be a map with one selector key.');
      continue;
    }
    final keys = entry.keys.whereType<String>().toList();
    if (keys.length != 1) {
      errors.add(
        '$entryWhere must have exactly one of: supertype, nameEndsWith, '
        'nameStartsWith, annotation.',
      );
      continue;
    }
    final key = keys.single;
    final raw = entry[key];
    if (raw is! String || raw.isEmpty) {
      errors.add('$entryWhere.$key must be a non-empty string.');
      continue;
    }
    switch (key) {
      case 'supertype':
        selectors.add(SupertypeSelector(raw));
      case 'nameEndsWith':
        selectors.add(NameEndsWithSelector(raw));
      case 'nameStartsWith':
        selectors.add(NameStartsWithSelector(raw));
      case 'annotation':
        selectors.add(AnnotationSelector(raw));
      default:
        errors.add("$entryWhere has unknown selector '$key'.");
    }
  }
  return selectors;
}
