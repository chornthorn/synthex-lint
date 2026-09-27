import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/placement/domain/placement_config.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  PlacementConfigParseResult parse(Object? document) =>
      parsePlacementConfig(document, matcher: matcher);

  Map<String, Object?> placement({
    Object? files = const ['lib/**/view_model/**'],
    Object? classesMustEndWith = 'ViewModel',
  }) => {'files': files, 'classesMustEndWith': classesMustEndWith};

  test('parses a placement with a single name suffix', () {
    final result = parse({
      'version': 1,
      'placements': [placement()],
    });

    expect(result.isValid, isTrue);
    final parsed = result.config!.placements.single;
    expect(parsed.files, ['lib/**/view_model/**']);
    expect(parsed.classesMustEndWith.map((entry) => entry.suffix), [
      'ViewModel',
    ]);
    expect(parsed.classesMustEndWith.single.excludesPrivate, isFalse);
    expect(parsed.exempt, isEmpty);
    expect(parsed.mustHaveSupertype, isEmpty);
    expect(parsed.mustNotHaveSupertype, isEmpty);
    expect(parsed.severity, isNull);
  });

  test('accepts a list for a name suffix', () {
    final result = parse({
      'placements': [
        placement(classesMustEndWith: ['Repository', 'DataSource']),
      ],
    });

    expect(
      result.config!.placements.single.classesMustEndWith.map(
        (entry) => entry.suffix,
      ),
      ['Repository', 'DataSource'],
    );
  });

  test('parses a suffix entry that exempts private classes', () {
    final result = parse({
      'placements': [
        placement(
          classesMustEndWith: [
            {'suffix': 'UseCase', 'exclude': 'private'},
            'Screen',
          ],
        ),
      ],
    });

    expect(result.isValid, isTrue);
    final parsed = result.config!.placements.single.classesMustEndWith;
    expect(parsed.map((entry) => entry.suffix), ['UseCase', 'Screen']);
    expect(parsed.first.excludesPrivate, isTrue);
    expect(parsed.last.excludesPrivate, isFalse);
  });

  test('parses a suffix entry on its own', () {
    final result = parse({
      'placements': [
        placement(
          classesMustEndWith: {'suffix': 'UseCase', 'exclude': 'private'},
        ),
      ],
    });

    final parsed = result.config!.placements.single.classesMustEndWith.single;
    expect(parsed.suffix, 'UseCase');
    expect(parsed.excludesPrivate, isTrue);
  });

  test('rejects an unknown key in a suffix entry', () {
    final result = parse({
      'placements': [
        placement(
          classesMustEndWith: [
            {'subfix': 'UseCase'},
          ],
        ),
      ],
    });

    expect(
      result.errors.single,
      contains("unknown key 'subfix' in a classesMustEndWith entry"),
    );
  });

  test('requires a suffix in a suffix entry', () {
    final result = parse({
      'placements': [
        placement(
          classesMustEndWith: [
            {'exclude': 'private'},
          ],
        ),
      ],
    });

    expect(
      result.errors.single,
      "placements[0]: a classesMustEndWith entry must declare a non-empty "
      "'suffix'.",
    );
  });

  test('rejects an unknown exclude value', () {
    final result = parse({
      'placements': [
        placement(
          classesMustEndWith: [
            {'suffix': 'UseCase', 'exclude': 'abstract'},
          ],
        ),
      ],
    });

    expect(
      result.errors.single,
      "placements[0]: 'exclude' must be 'private', not 'abstract'.",
    );
  });

  test('rejects a suffix entry that is not a map or a string', () {
    final result = parse({
      'placements': [
        placement(classesMustEndWith: [1]),
      ],
    });

    expect(
      result.errors.single,
      "placements[0]: 'classesMustEndWith' must hold suffixes, or maps with a "
      "'suffix' and an optional 'exclude'.",
    );
  });

  test('accepts a single glob string for files', () {
    final result = parse({
      'placements': [placement(files: 'lib/**')],
    });

    expect(result.config!.placements.single.files, ['lib/**']);
  });

  test('parses exempt patterns', () {
    final result = parse({
      'placements': [
        {
          'files': ['lib/**'],
          'exempt': ['**/*.g.dart'],
          'classesMustEndWith': 'ViewModel',
        },
      ],
    });

    expect(result.config!.placements.single.exempt, ['**/*.g.dart']);
  });

  test('parses supertype requirements', () {
    final result = parse({
      'placements': [
        {
          'files': ['lib/**'],
          'mustHaveSupertype': 'ChangeNotifier',
          'mustNotHaveSupertype': ['Repository', 'DataSource'],
        },
      ],
    });

    final parsed = result.config!.placements.single;
    expect(parsed.mustHaveSupertype, ['ChangeNotifier']);
    expect(parsed.mustNotHaveSupertype, ['Repository', 'DataSource']);
  });

  test('defaults the severity to info', () {
    final result = parse({
      'placements': [placement()],
    });

    expect(result.config!.severity, RuleSeverity.info);
  });

  test('parses the config-wide severity', () {
    final result = parse({
      'severity': 'error',
      'placements': [placement()],
    });

    expect(result.config!.severity, RuleSeverity.error);
  });

  test('parses a per-placement severity override', () {
    final result = parse({
      'severity': 'warning',
      'placements': [
        {...placement(), 'severity': 'error'},
      ],
    });

    final parsed = result.config!.placements.single;
    expect(parsed.severity, RuleSeverity.error);
    expect(parsed.severityFor(result.config!.severity), RuleSeverity.error);
  });

  test('falls back to the config severity', () {
    final result = parse({
      'severity': 'warning',
      'placements': [placement()],
    });

    expect(
      result.config!.placements.single.severityFor(result.config!.severity),
      RuleSeverity.warning,
    );
  });

  test('rejects a non-map document', () {
    expect(parse('nope').errors, ['The config must be a map.']);
  });

  test('rejects an unsupported version', () {
    final result = parse({
      'version': 2,
      'placements': [placement()],
    });

    expect(result.errors, ['Unsupported version: 2 (expected 1).']);
  });

  test('requires placements', () {
    expect(parse({'version': 1}).errors, [
      "'placements' must be a non-empty list.",
    ]);
    expect(parse({'placements': []}).errors, [
      "'placements' must be a non-empty list.",
    ]);
  });

  test('rejects a placement that is not a map', () {
    expect(
      parse({
        'placements': ['nope'],
      }).errors,
      ['placements[0] must be a map.'],
    );
  });

  test('rejects an unknown key', () {
    final result = parse({
      'placements': [
        {...placement(), 'classesMustStartWith': 'Home'},
      ],
    });

    expect(
      result.errors.single,
      contains("unknown key 'classesMustStartWith'"),
    );
  });

  test('requires files', () {
    final result = parse({
      'placements': [
        {'classesMustEndWith': 'ViewModel'},
      ],
    });

    expect(result.errors, ["placements[0]: 'files' is required."]);
  });

  test('requires at least one check', () {
    final result = parse({
      'placements': [
        {
          'files': ['lib/**'],
        },
      ],
    });

    expect(result.errors.single, contains('must declare at least one of'));
  });

  test('rejects an absolute pattern', () {
    final result = parse({
      'placements': [
        {
          'files': ['/lib/**'],
          'classesMustEndWith': 'ViewModel',
        },
      ],
    });

    expect(
      result.errors.single,
      "placements[0]: pattern '/lib/**' must be relative to the package root.",
    );
  });

  test('rejects an invalid glob', () {
    final result = parse({
      'placements': [
        {
          'files': ['lib/[', 'lib/**'],
          'classesMustEndWith': 'ViewModel',
        },
      ],
    });

    expect(result.errors.single, contains("invalid pattern 'lib/['"));
  });

  test('rejects a malformed string list', () {
    final result = parse({
      'placements': [
        placement(classesMustEndWith: ['']),
      ],
    });

    expect(
      result.errors.single,
      "placements[0]: 'classesMustEndWith' must hold non-empty suffixes.",
    );
  });

  test('rejects an invalid severity', () {
    final result = parse({
      'severity': 'fatal',
      'placements': [placement()],
    });

    expect(result.errors, [
      "severity: invalid severity 'fatal' (expected info, warning, or error).",
    ]);
  });

  test('collects every error', () {
    final result = parse({
      'version': 2,
      'placements': [
        {
          'files': ['/lib/**'],
        },
      ],
    });

    expect(result.errors, hasLength(3));
  });
}
