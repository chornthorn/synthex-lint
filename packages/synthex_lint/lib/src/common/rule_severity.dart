/// The severity of a rule violation.
///
/// Configured in the rule's schema, so each rule can be as strict as the
/// project needs.
enum RuleSeverity {
  /// An informational violation.
  info,

  /// A warning-level violation.
  warning,

  /// An error-level violation.
  error;

  /// Parses a schema value, returning `null` for unknown values.
  static RuleSeverity? parse(Object? value) => switch (value) {
    'info' => RuleSeverity.info,
    'warning' => RuleSeverity.warning,
    'error' => RuleSeverity.error,
    _ => null,
  };
}

/// Parses a severity value from a config document, recording a config error
/// for unknown values.
RuleSeverity? parseRuleSeverity(
  Object? value, {
  required String where,
  required List<String> errors,
}) {
  if (value == null) return null;
  final severity = RuleSeverity.parse(value);
  if (severity == null) {
    errors.add(
      "$where: invalid severity '$value' (expected info, warning, or error).",
    );
  }
  return severity;
}
