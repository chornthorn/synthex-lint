import 'package:synthex_lint/src/common/config_patterns.dart';
import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  List<String>? parse(Object? value, {bool isRequired = false}) {
    final errors = <String>[];
    final result = parseConfigPatterns(
      value,
      where: 'where',
      field: 'files',
      matcher: matcher,
      errors: errors,
      isRequired: isRequired,
    );
    expect(errors, isEmpty);
    return result;
  }

  List<String> errors(Object? value, {bool isRequired = false}) {
    final collected = <String>[];
    parseConfigPatterns(
      value,
      where: 'where',
      field: 'files',
      matcher: matcher,
      errors: collected,
      isRequired: isRequired,
    );
    return collected;
  }

  group('parseConfigPatterns', () {
    test('reads a single pattern', () {
      expect(parse('lib/**'), ['lib/**']);
    });

    test('reads a list of patterns', () {
      expect(parse(['lib/**', 'test/**']), ['lib/**', 'test/**']);
    });

    test('returns null when the value is absent', () {
      expect(parse(null), isNull);
    });

    test('reports a missing required value', () {
      expect(errors(null, isRequired: true), ["where: 'files' is required."]);
    });

    test('reports an empty required list', () {
      expect(errors(const <String>[], isRequired: true), [
        "where: 'files' must not be empty.",
      ]);
    });

    test('reports a value that is neither a string nor a list', () {
      expect(errors(42), [
        "where: 'files' must be a string or a list of strings.",
      ]);
    });

    test('reports a non-string entry', () {
      expect(errors([1]), ["where: 'files' must contain non-empty strings."]);
    });

    test('reports an absolute pattern', () {
      expect(errors(['/lib/**']), [
        "where: pattern '/lib/**' must be relative to the package root.",
      ]);
    });

    test('reports a pattern that does not compile', () {
      final reported = errors(['lib/[']);
      expect(reported.single, contains("invalid pattern 'lib/['"));
    });
  });

  group('parseConfigStrings', () {
    List<String>? parseStrings(Object? value, {List<String>? errors}) =>
        parseConfigStrings(
          value,
          where: 'where',
          field: 'names',
          errors: errors ?? [],
        );

    test('reads a single string', () {
      expect(parseStrings('ViewModel'), ['ViewModel']);
    });

    test('reads a list', () {
      expect(parseStrings(['A', 'B']), ['A', 'B']);
    });

    test('returns null when the value is absent', () {
      expect(parseStrings(null), isNull);
    });

    test('reports an empty string', () {
      final reported = <String>[];
      parseStrings('', errors: reported);
      expect(reported, ["where: 'names' must be a non-empty string."]);
    });
  });
}
