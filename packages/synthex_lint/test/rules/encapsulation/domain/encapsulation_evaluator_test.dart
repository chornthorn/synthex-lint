import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/encapsulation/domain/encapsulation_config.dart';
import 'package:synthex_lint/src/rules/encapsulation/domain/encapsulation_evaluator.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();

  List<EncapsulationViolation> evaluate(
    List<Encapsulation> encapsulations, {
    String path = 'lib/src/view_models/home.dart',
    required ClassFacts facts,
    RuleSeverity severity = RuleSeverity.info,
  }) => EncapsulationEvaluator(
    config: EncapsulationConfig(
      version: 1,
      severity: severity,
      encapsulations: encapsulations,
    ),
    matcher: matcher,
  ).evaluateClass(path: path, facts: facts);

  Encapsulation byFile({
    List<String> files = const ['lib/**/view_models/**'],
    Map<String, bool> requirements = const {fieldsPrivateRequirement: true},
    Map<String, RuleSeverity> severities = const {},
    RuleSeverity? severity,
  }) => Encapsulation(
    files: files,
    requirements: requirements,
    severities: severities,
    severity: severity,
  );

  test('reports a public instance field', () {
    final violations = evaluate(
      [byFile()],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations.map((v) => v.message), [
      "HomeViewModel: field 'count' must be private; expose it through a "
          'public getter.',
    ]);
    expect(violations.single.member.kind, MemberKind.field);
    expect(violations.single.member.name, 'count');
  });

  test('reports a private field that is not final', () {
    final violations = evaluate(
      [
        byFile(requirements: const {privateFieldsFinalRequirement: true}),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: '_title')],
      ),
    );

    expect(violations.map((v) => v.message), [
      "HomeViewModel: private field '_title' must be final; mutate this state "
          'through methods.',
    ]);
  });

  test('reports a public setter', () {
    final violations = evaluate(
      [
        byFile(requirements: const {noPublicSettersRequirement: true}),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        accessors: [AccessorFacts(name: 'title', isGetter: false)],
      ),
    );

    expect(violations.map((v) => v.message), [
      "HomeViewModel: setter 'title' must not be public; expose read-only "
          'state and mutate through methods.',
    ]);
    expect(violations.single.member.kind, MemberKind.setter);
  });

  test('reports a private field with no public getter', () {
    final violations = evaluate(
      [
        byFile(requirements: const {requirePublicGettersRequirement: true}),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: '_title', isFinal: true)],
      ),
    );

    expect(violations.map((v) => v.message), [
      "HomeViewModel: private field '_title' has no public getter 'title'.",
    ]);
  });

  test('accepts a private field exposed by a public getter', () {
    final violations = evaluate(
      [
        byFile(requirements: const {requirePublicGettersRequirement: true}),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: '_title', isFinal: true)],
        accessors: [AccessorFacts(name: 'title', isGetter: true)],
      ),
    );

    expect(violations, isEmpty);
  });

  test('ignores static members', () {
    final violations = evaluate(
      [
        byFile(
          requirements: const {
            fieldsPrivateRequirement: true,
            privateFieldsFinalRequirement: true,
            noPublicSettersRequirement: true,
          },
        ),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [
          FieldFacts(name: 'count', isStatic: true),
          FieldFacts(name: '_title', isStatic: true),
        ],
        accessors: [
          AccessorFacts(name: 'title', isGetter: false, isStatic: true),
        ],
      ),
    );

    expect(violations, isEmpty);
  });

  test('selects by file glob', () {
    final violations = evaluate(
      [
        byFile(files: const ['lib/**/pages/*']),
      ],
      path: 'lib/src/pages/home_page.dart',
      facts: const ClassFacts(
        name: 'HomePage',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations, hasLength(1));
  });

  test('ignores classes in files no encapsulation selects', () {
    final violations = evaluate(
      [byFile()],
      path: 'lib/src/pages/home_page.dart',
      facts: const ClassFacts(
        name: 'HomePage',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations, isEmpty);
  });

  test('selects by supertype', () {
    final violations = evaluate(
      [
        Encapsulation(
          selectors: const [SupertypeSelector('ChangeNotifier')],
          requirements: const {fieldsPrivateRequirement: true},
        ),
      ],
      path: 'lib/src/anything.dart',
      facts: const ClassFacts(
        name: 'Cart',
        supertypeNames: ['ChangeNotifier', 'Object'],
        fields: [FieldFacts(name: 'total')],
      ),
    );

    expect(violations, hasLength(1));
  });

  test('selects by name suffix', () {
    final violations = evaluate(
      [
        Encapsulation(
          selectors: const [NameEndsWithSelector('ViewModel')],
          requirements: const {fieldsPrivateRequirement: true},
        ),
      ],
      path: 'lib/src/anything.dart',
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations, hasLength(1));
  });

  test('selects by annotation', () {
    final violations = evaluate(
      [
        Encapsulation(
          selectors: const [AnnotationSelector('viewModel')],
          requirements: const {fieldsPrivateRequirement: true},
        ),
      ],
      path: 'lib/src/anything.dart',
      facts: const ClassFacts(
        name: 'Cart',
        annotations: ['viewModel'],
        fields: [FieldFacts(name: 'total')],
      ),
    );

    expect(violations, hasLength(1));
  });

  test('applies every selecting encapsulation', () {
    final violations = evaluate(
      [
        byFile(),
        Encapsulation(
          selectors: const [NameEndsWithSelector('ViewModel')],
          requirements: const {noPublicSettersRequirement: true},
        ),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: 'count')],
        accessors: [AccessorFacts(name: 'title', isGetter: false)],
      ),
    );

    expect(violations, hasLength(2));
  });

  test('uses the per-encapsulation severity', () {
    final violations = evaluate(
      [byFile(severity: RuleSeverity.error)],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations.single.severity, RuleSeverity.error);
  });

  test('prefers the per-requirement severity', () {
    final violations = evaluate(
      [
        byFile(
          severity: RuleSeverity.warning,
          severities: const {fieldsPrivateRequirement: RuleSeverity.error},
        ),
      ],
      facts: const ClassFacts(
        name: 'HomeViewModel',
        fields: [FieldFacts(name: 'count')],
      ),
    );

    expect(violations.single.severity, RuleSeverity.error);
  });
}
