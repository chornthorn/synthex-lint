import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/placement/domain/placement_config.dart';
import 'package:synthex_lint/src/rules/placement/domain/placement_evaluator.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  List<PlacementViolation> evaluate(
    List<Placement> placements, {
    required String path,
    required ClassFacts facts,
    RuleSeverity severity = RuleSeverity.info,
  }) => PlacementEvaluator(
    config: PlacementConfig(
      version: 1,
      severity: severity,
      placements: placements,
    ),
    matcher: matcher,
  ).evaluateClass(path: path, facts: facts);

  Placement nameEndsWith(List<String> suffixes) => Placement(
    files: const ['lib/**/view_model/**'],
    classesMustEndWith: [
      for (final suffix in suffixes) RequiredSuffix(suffix: suffix),
    ],
  );

  /// A placement for `use_cases/`: public classes carry the suffix, private
  /// ones are exempt.
  Placement useCasePlacement() => Placement(
    files: const ['lib/**/use_cases/**'],
    classesMustEndWith: const [
      RequiredSuffix(suffix: 'UseCase', excludesPrivate: true),
    ],
  );

  test('reports a class whose name misses the required suffix', () {
    final violations = evaluate(
      [
        nameEndsWith(['ViewModel']),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'Home'),
    );

    expect(violations.map((v) => v.message), [
      "Home: name must end with 'ViewModel'.",
    ]);
  });

  test('accepts a class whose name carries the required suffix', () {
    final violations = evaluate(
      [
        nameEndsWith(['ViewModel']),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'HomeViewModel'),
    );

    expect(violations, isEmpty);
  });

  test('accepts any of several suffixes', () {
    final violations = evaluate(
      [
        nameEndsWith(['Repository', 'DataSource']),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'RemoteDataSource'),
    );

    expect(violations, isEmpty);
  });

  test('accepts a private class where the suffix exempts private classes', () {
    final violations = evaluate(
      [useCasePlacement()],
      path: 'lib/domain/use_cases/load_profile.dart',
      facts: const ClassFacts(name: '_Cache'),
    );

    expect(violations, isEmpty);
  });

  test('reports a public class where the suffix exempts private classes', () {
    final violations = evaluate(
      [useCasePlacement()],
      path: 'lib/domain/use_cases/load_profile.dart',
      facts: const ClassFacts(name: 'LoadProfile'),
    );

    expect(violations.map((v) => v.message), [
      "LoadProfile: name must end with 'UseCase'.",
    ]);
  });

  test('reports a private class where the suffix does not exempt them', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**'],
          classesMustEndWith: const [RequiredSuffix(suffix: 'UseCase')],
        ),
      ],
      path: 'lib/domain/use_cases/load_profile.dart',
      facts: const ClassFacts(name: '_Cache'),
    );

    expect(violations.map((v) => v.message), [
      "_Cache: name must end with 'UseCase'.",
    ]);
  });

  test('checks an exempt class against the remaining suffixes', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**'],
          classesMustEndWith: const [
            RequiredSuffix(suffix: 'UseCase', excludesPrivate: true),
            RequiredSuffix(suffix: 'Screen'),
          ],
        ),
      ],
      path: 'lib/domain/use_cases/load_profile.dart',
      facts: const ClassFacts(name: '_Cache'),
    );

    expect(violations.map((v) => v.message), [
      "_Cache: name must end with 'Screen'.",
    ]);
  });

  test('lists the suffixes when several are allowed', () {
    final violations = evaluate(
      [
        nameEndsWith(['Repository', 'DataSource']),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'Home'),
    );

    expect(violations.map((v) => v.message), [
      "Home: name must end with one of 'Repository', 'DataSource'.",
    ]);
  });

  test('reports a class that does not have the required supertype', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**/data/**'],
          mustHaveSupertype: const ['Repository'],
        ),
      ],
      path: 'lib/src/data/repository.dart',
      facts: const ClassFacts(name: 'FakeRepository'),
    );

    expect(violations.map((v) => v.message), [
      "FakeRepository: must extend or implement 'Repository'.",
    ]);
  });

  test('accepts a transitive supertype', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**/data/**'],
          mustHaveSupertype: const ['Repository'],
        ),
      ],
      path: 'lib/src/data/repository.dart',
      facts: const ClassFacts(
        name: 'InMemoryRepository',
        supertypeNames: ['Repository', 'Object'],
      ),
    );

    expect(violations, isEmpty);
  });

  test('reports a class with a forbidden supertype', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**/presentation/**'],
          mustNotHaveSupertype: const ['ChangeNotifier'],
        ),
      ],
      path: 'lib/src/presentation/home.dart',
      facts: const ClassFacts(
        name: 'HomeScreen',
        supertypeNames: ['ChangeNotifier', 'Object'],
      ),
    );

    expect(violations.map((v) => v.message), [
      "HomeScreen: must not extend or implement 'ChangeNotifier'.",
    ]);
  });

  test('ignores files no placement matches', () {
    final violations = evaluate(
      [
        nameEndsWith(['ViewModel']),
      ],
      path: 'lib/src/presentation/home.dart',
      facts: const ClassFacts(name: 'Home'),
    );

    expect(violations, isEmpty);
  });

  test('ignores an exempt file', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**'],
          exempt: const ['**/*.g.dart'],
          classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
        ),
      ],
      path: 'lib/src/view_model/home.g.dart',
      facts: const ClassFacts(name: 'Home'),
    );

    expect(violations, isEmpty);
  });

  test('applies every matching placement', () {
    final violations = evaluate(
      [
        nameEndsWith(['ViewModel']),
        Placement(
          files: const ['lib/**/view_model/**'],
          mustNotHaveSupertype: const ['ChangeNotifier'],
        ),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'Home', supertypeNames: ['ChangeNotifier']),
    );

    expect(violations.map((v) => v.message), [
      "Home: name must end with 'ViewModel'.",
      "Home: must not extend or implement 'ChangeNotifier'.",
    ]);
  });

  test('uses the per-placement severity', () {
    final violations = evaluate(
      [
        Placement(
          files: const ['lib/**/view_model/**'],
          classesMustEndWith: const [RequiredSuffix(suffix: 'ViewModel')],
          severity: RuleSeverity.error,
        ),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'Home'),
    );

    expect(violations.single.severity, RuleSeverity.error);
  });

  test('falls back to the config severity', () {
    final violations = evaluate(
      [
        nameEndsWith(['ViewModel']),
      ],
      path: 'lib/src/view_model/home.dart',
      facts: const ClassFacts(name: 'Home'),
      severity: RuleSeverity.warning,
    );

    expect(violations.single.severity, RuleSeverity.warning);
  });
}
