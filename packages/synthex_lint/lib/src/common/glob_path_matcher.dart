import 'package:glob/glob.dart';

import 'path_matcher.dart';

/// A [PathMatcher] backed by `package:glob`.
///
/// Patterns without wildcards are compared for exact equality, which also
/// keeps non-path values such as `dart:io` away from the glob parser.
///
/// Compiled patterns are cached: constructing a [Glob] parses the pattern into
/// an AST, and the architecture rule evaluates every import of every file
/// against every layer pattern, so re-parsing per match dominates the rule's
/// CPU time.
class GlobPathMatcher implements PathMatcher {
  GlobPathMatcher();

  final Map<String, Glob> _globCache = {};

  @override
  String? validate(String pattern) {
    try {
      _globFor(pattern);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  @override
  bool matches(String pattern, String value) {
    if (!_containsWildcards(pattern)) return pattern == value;
    return _globFor(pattern).matches(value);
  }

  Glob _globFor(String pattern) =>
      _globCache.putIfAbsent(pattern, () => Glob(pattern));

  static bool _containsWildcards(String pattern) =>
      pattern.contains('*') || pattern.contains('?') || pattern.contains('[');
}
