import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/encapsulation/domain/encapsulation_config.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  EncapsulationConfigParseResult parse(Object? document) =>
      parseEncapsulationConfig(document, matcher: matcher);

  Map<String, Object?> encapsulation({
    Object? files = const ['lib/**/view_models/*'],
    Object? requirements = const {'fieldsPrivate': true},
  }) => {'files': files, 'requirements': requirements};

  test('parses an encapsulation selected by file glob', () {
    final result = parse({
      'version': 1,
      'encapsulations': [encapsulation()],
    });

    expect(result.isValid, isTrue);
    final parsed = result.config!.encapsulations.single;
    expect(parsed.files, ['lib/**/view_models/*']);
    expect(parsed.selectors, isEmpty);
    expect(parsed.isEnabled(fieldsPrivateRequirement), isTrue);
    expect(parsed.severity, isNull);
  });

  test('fills in the requirement defaults', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
        },
      ],
    });

    final parsed = result.config!.encapsulations.single;
    expect(parsed.isEnabled(fieldsPrivateRequirement), isTrue);
    expect(parsed.isEnabled(privateFieldsFinalRequirement), isTrue);
    expect(parsed.isEnabled(noPublicSettersRequirement), isTrue);
    expect(parsed.isEnabled(requirePublicGettersRequirement), isFalse);
  });

  test('parses an encapsulation selected by supertype', () {
    final result = parse({
      'encapsulations': [
        {
          'selectors': [
            {'supertype': 'ChangeNotifier'},
            {'nameEndsWith': 'ViewModel'},
            {'nameStartsWith': 'Home'},
            {'annotation': 'viewModel'},
          ],
          'requirements': {'fieldsPrivate': true},
        },
      ],
    });

    final parsed = result.config!.encapsulations.single;
    expect(parsed.files, isEmpty);
    expect(parsed.selectors, hasLength(4));
    expect(parsed.selectors.first, isA<SupertypeSelector>());
  });

  test('accepts files and selectors together', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'selectors': [
            {'supertype': 'ChangeNotifier'},
          ],
          'requirements': {'fieldsPrivate': true},
        },
      ],
    });

    final parsed = result.config!.encapsulations.single;
    expect(parsed.files, ['lib/**']);
    expect(parsed.selectors, hasLength(1));
  });

  test('parses several encapsulations', () {
    final result = parse({
      'encapsulations': [
        encapsulation(),
        encapsulation(files: const ['lib/**/pages/*']),
      ],
    });

    expect(result.config!.encapsulations, hasLength(2));
  });

  test('defaults the severity to info', () {
    final result = parse({
      'encapsulations': [encapsulation()],
    });

    expect(result.config!.severity, RuleSeverity.info);
  });

  test('parses the config-wide severity', () {
    final result = parse({
      'severity': 'warning',
      'encapsulations': [encapsulation()],
    });

    expect(result.config!.severity, RuleSeverity.warning);
  });

  test('parses a per-encapsulation severity override', () {
    final result = parse({
      'severity': 'warning',
      'encapsulations': [
        {...encapsulation(), 'severity': 'error'},
      ],
    });

    final config = result.config!;
    expect(
      config.encapsulations.single.severityFor(
        fieldsPrivateRequirement,
        config.severity,
      ),
      RuleSeverity.error,
    );
  });

  test('parses a per-requirement severity override', () {
    final result = parse({
      'severity': 'info',
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': {'fieldsPrivate': true},
          'severities': {'fieldsPrivate': 'error'},
        },
      ],
    });

    final config = result.config!;
    expect(
      config.encapsulations.single.severityFor(
        fieldsPrivateRequirement,
        config.severity,
      ),
      RuleSeverity.error,
    );
  });

  test('parses a list of requirement entries', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {'fieldsPrivate': true},
            {'privateFieldsFinal': false},
          ],
        },
      ],
    });

    final parsed = result.config!.encapsulations.single;
    expect(parsed.isEnabled(fieldsPrivateRequirement), isTrue);
    expect(parsed.isEnabled(privateFieldsFinalRequirement), isFalse);
    // A requirement the list does not name keeps its default.
    expect(parsed.isEnabled(noPublicSettersRequirement), isTrue);
  });

  test('parses requirement settings in a list entry', () {
    final result = parse({
      'severity': 'info',
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {
              'fieldsPrivate': {'enabled': true, 'severity': 'warning'},
            },
            {'noPublicSetters': false},
          ],
        },
      ],
    });

    final config = result.config!;
    final parsed = config.encapsulations.single;
    expect(parsed.isEnabled(fieldsPrivateRequirement), isTrue);
    expect(
      parsed.severityFor(fieldsPrivateRequirement, config.severity),
      RuleSeverity.warning,
    );
  });

  test('keeps a requirement default when its settings omit enabled', () {
    final result = parse({
      'severity': 'info',
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {
              'fieldsPrivate': {'severity': 'error'},
            },
          ],
        },
      ],
    });

    final config = result.config!;
    final parsed = config.encapsulations.single;
    // `fieldsPrivate` defaults to true, so naming only its severity leaves it on.
    expect(parsed.isEnabled(fieldsPrivateRequirement), isTrue);
    expect(
      parsed.severityFor(fieldsPrivateRequirement, config.severity),
      RuleSeverity.error,
    );
  });

  test('lets a list entry severity win over the severities map', () {
    final result = parse({
      'severity': 'info',
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {
              'fieldsPrivate': {'enabled': true, 'severity': 'error'},
            },
          ],
          'severities': {'fieldsPrivate': 'warning'},
        },
      ],
    });

    final config = result.config!;
    expect(
      config.encapsulations.single.severityFor(
        fieldsPrivateRequirement,
        config.severity,
      ),
      RuleSeverity.error,
    );
  });

  test('rejects requirements that are neither a map nor a list', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': 'fieldsPrivate',
        },
      ],
    });

    expect(
      result.errors.single,
      contains(
        "'requirements' must be a map of requirement names to booleans, or a "
        'list of requirement entries.',
      ),
    );
  });

  test('rejects a requirement entry that names two requirements', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {'fieldsPrivate': true, 'noPublicSetters': true},
          ],
        },
      ],
    });

    expect(result.errors.single, contains('must name exactly one requirement'));
  });

  test('rejects a requirement entry that is not a map', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': ['fieldsPrivate'],
        },
      ],
    });

    expect(
      result.errors.single,
      'encapsulations[0].requirements[0] must name one requirement.',
    );
  });

  test('rejects settings left beside a requirement name', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {'fieldsPrivate': null, 'enabled': true, 'severity': 'warning'},
          ],
        },
      ],
    });

    expect(
      result.errors.single,
      contains("put 'enabled' and 'severity' under 'fieldsPrivate'"),
    );
  });

  test('rejects an unknown key in requirement settings', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': [
            {
              'fieldsPrivate': {'enabled': true, 'severityLevel': 'warning'},
            },
          ],
        },
      ],
    });

    expect(result.errors.single, contains("unknown key 'severityLevel'"));
  });

  test('falls back to the config severity', () {
    final result = parse({
      'severity': 'warning',
      'encapsulations': [encapsulation()],
    });

    final config = result.config!;
    expect(
      config.encapsulations.single.severityFor(
        fieldsPrivateRequirement,
        config.severity,
      ),
      RuleSeverity.warning,
    );
  });

  test('rejects a non-map document', () {
    expect(parse('nope').errors, ['The config must be a map.']);
  });

  test('rejects an unsupported version', () {
    final result = parse({
      'version': 2,
      'encapsulations': [encapsulation()],
    });

    expect(result.errors, ['Unsupported version: 2 (expected 1).']);
  });

  test('requires encapsulations', () {
    expect(parse({'version': 1}).errors, [
      "'encapsulations' must be a non-empty list.",
    ]);
  });

  test('rejects an encapsulation that is not a map', () {
    expect(
      parse({
        'encapsulations': ['nope'],
      }).errors,
      ['encapsulations[0] must be a map.'],
    );
  });

  test('rejects an unknown key', () {
    final result = parse({
      'encapsulations': [
        {...encapsulation(), 'selectorss': []},
      ],
    });

    expect(result.errors.single, contains("unknown key 'selectorss'"));
  });

  test('requires files or selectors', () {
    final result = parse({
      'encapsulations': [
        {
          'requirements': {'fieldsPrivate': true},
        },
      ],
    });

    expect(result.errors, [
      "encapsulations[0] must select classes with 'files' or 'selectors'.",
    ]);
  });

  test('rejects an unknown requirement', () {
    final result = parse({
      'encapsulations': [
        encapsulation(requirements: const {'fieldsPublic': true}),
      ],
    });

    expect(
      result.errors.single,
      contains("unknown requirement 'fieldsPublic'"),
    );
  });

  test('rejects a requirement that is not a boolean', () {
    final result = parse({
      'encapsulations': [
        encapsulation(requirements: const {'fieldsPrivate': 'yes'}),
      ],
    });

    expect(result.errors.single, contains('must be true or false'));
  });

  test('requires at least one enabled requirement', () {
    final result = parse({
      'encapsulations': [
        encapsulation(
          requirements: const {
            'fieldsPrivate': false,
            'privateFieldsFinal': false,
            'noPublicSetters': false,
            'requirePublicGetters': false,
          },
        ),
      ],
    });

    expect(result.errors.single, contains('at least one requirement'));
  });

  test('rejects an unknown requirement in severities', () {
    final result = parse({
      'encapsulations': [
        {
          'files': ['lib/**'],
          'requirements': {'fieldsPrivate': true},
          'severities': {'fieldsPublic': 'error'},
        },
      ],
    });

    expect(
      result.errors.single,
      contains("unknown requirement in 'severities': 'fieldsPublic'"),
    );
  });

  test('rejects an unknown selector', () {
    final result = parse({
      'encapsulations': [
        {
          'selectors': [
            {'path': 'lib/**'},
          ],
          'requirements': {'fieldsPrivate': true},
        },
      ],
    });

    expect(result.errors.single, contains("unknown selector 'path'"));
  });

  test('rejects a selector with several keys', () {
    final result = parse({
      'encapsulations': [
        {
          'selectors': [
            {'supertype': 'A', 'nameEndsWith': 'B'},
          ],
          'requirements': {'fieldsPrivate': true},
        },
      ],
    });

    expect(result.errors.single, contains('exactly one of'));
  });
}
