/// Parsing helpers for the list-shaped values a rule config can hold.
///
/// Every rule collects errors instead of failing fast, so these helpers record
/// what is wrong in the caller's [errors] list and return what they could
/// parse.
library;

import 'path_matcher.dart';

/// Parses a config value that holds one glob pattern or a list of them.
///
/// Returns `null` when [value] is absent, and an empty list when it is
/// malformed. Patterns must be relative to the package root and must compile,
/// so a configuration error is reported at analysis time instead of silently
/// matching nothing.
List<String>? parseConfigPatterns(
  Object? value, {
  required String where,
  required String field,
  required PathMatcher matcher,
  required List<String> errors,
  bool isRequired = false,
}) {
  final patterns = parseConfigStrings(
    value,
    where: where,
    field: field,
    errors: errors,
  );
  if (patterns == null) {
    if (isRequired) {
      errors.add("$where: '$field' is required.");
      return const [];
    }
    return null;
  }
  if (isRequired && patterns.isEmpty) {
    errors.add("$where: '$field' must not be empty.");
  }
  for (final pattern in patterns) {
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
  return patterns;
}

/// Parses a value that is a single string or a list of strings, returning
/// `null` when it is absent and an empty list when it is malformed (with an
/// error recorded).
List<String>? parseConfigStrings(
  Object? value, {
  required String where,
  required String field,
  required List<String> errors,
}) {
  if (value == null) return null;
  if (value is String) {
    if (value.isEmpty) {
      errors.add("$where: '$field' must be a non-empty string.");
      return const [];
    }
    return [value];
  }
  if (value is! List) {
    errors.add("$where: '$field' must be a string or a list of strings.");
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
  return result;
}
