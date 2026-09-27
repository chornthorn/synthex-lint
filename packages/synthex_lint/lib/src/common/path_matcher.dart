/// Matches package-relative paths and import URIs against user-provided
/// patterns.
///
/// Declared in the domain layer, implemented in the infrastructure layer, so
/// the domain stays free of third-party dependencies.
abstract interface class PathMatcher {
  /// Returns an error message when [pattern] cannot be used, else `null`.
  String? validate(String pattern);

  /// Whether [value] matches [pattern].
  bool matches(String pattern, String value);
}
