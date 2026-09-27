import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';
import 'placement_config.dart';

/// The facts about a class declaration that placement checks depend on.
class ClassFacts {
  /// Creates the facts about the class named [name].
  const ClassFacts({required this.name, this.supertypeNames = const []});

  /// The class name.
  final String name;

  /// Simple names of all direct and indirect supertypes, interfaces, and
  /// mixins.
  final List<String> supertypeNames;
}

/// A single placement violation.
class PlacementViolation {
  /// Creates a violation with its diagnostic [message] and [severity].
  const PlacementViolation({required this.message, required this.severity});

  /// A human-readable description, used as the diagnostic message.
  final String message;

  /// The severity configured for this violation.
  final RuleSeverity severity;

  @override
  String toString() => message;
}

/// Evaluates class declarations against a [PlacementConfig].
///
/// Pure: no analyzer, no file system, no state.
class PlacementEvaluator {
  /// Creates an evaluator for [config] that matches paths with [matcher].
  const PlacementEvaluator({required this.config, required this.matcher});

  /// The config to evaluate against.
  final PlacementConfig config;

  /// The matcher that `files` patterns are matched with.
  final PathMatcher matcher;

  /// All violations for the class described by [facts], declared in [path].
  ///
  /// Every placement whose `files` match [path] applies, so a class can be
  /// constrained by more than one placement. An exempt path is governed by
  /// none of them.
  List<PlacementViolation> evaluateClass({
    required String path,
    required ClassFacts facts,
  }) {
    final violations = <PlacementViolation>[];
    for (final placement in config.placements) {
      if (!_governs(placement, path)) continue;
      final severity = placement.severityFor(config.severity);

      // A suffix that exempts private classes does not apply to them, so the
      // requirement a class is checked against is the rest of the suffixes.
      final suffixes = [
        for (final required in placement.classesMustEndWith)
          if (required.appliesTo(facts.name)) required.suffix,
      ];
      if (suffixes.isNotEmpty && !suffixes.any(facts.name.endsWith)) {
        violations.add(
          PlacementViolation(
            message: '${facts.name}: ${_suffixRequirement(suffixes)}',
            severity: severity,
          ),
        );
      }

      final required = placement.mustHaveSupertype;
      if (required.isNotEmpty && !required.any(facts.supertypeNames.contains)) {
        violations.add(
          PlacementViolation(
            message: '${facts.name}: ${_supertypeRequirement(required)}',
            severity: severity,
          ),
        );
      }

      for (final forbidden in placement.mustNotHaveSupertype) {
        if (facts.supertypeNames.contains(forbidden)) {
          violations.add(
            PlacementViolation(
              message:
                  '${facts.name}: must not extend or implement '
                  "'$forbidden'.",
              severity: severity,
            ),
          );
        }
      }
    }
    return violations;
  }

  /// Whether [placement] governs a class declared in [path].
  bool _governs(Placement placement, String path) {
    if (!placement.files.any((pattern) => matcher.matches(pattern, path))) {
      return false;
    }
    return !placement.exempt.any((pattern) => matcher.matches(pattern, path));
  }
}

String _quoted(List<String> names) => names.map((name) => "'$name'").join(', ');

/// `name must end with 'X'.`, or `name must end with one of 'X', 'Y'.`
String _suffixRequirement(List<String> suffixes) => suffixes.length == 1
    ? "name must end with '${suffixes.single}'."
    : 'name must end with one of ${_quoted(suffixes)}.';

/// `must extend or implement 'X'.`, or `must extend or implement one of
/// 'X', 'Y'.`
String _supertypeRequirement(List<String> names) => names.length == 1
    ? "must extend or implement '${names.single}'."
    : 'must extend or implement one of ${_quoted(names)}.';
