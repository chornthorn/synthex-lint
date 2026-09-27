import '../../../common/path_matcher.dart';
import '../../../common/rule_severity.dart';
import 'encapsulation_config.dart';

/// The kind of class member a violation points at.
enum MemberKind {
  /// An instance field.
  field,

  /// A getter.
  getter,

  /// A setter.
  setter,
}

/// A reference to the class member a violation points at.
class MemberRef {
  /// Creates a reference to the [kind] member named [name].
  const MemberRef(this.kind, this.name);

  /// The kind of member.
  final MemberKind kind;

  /// The simple member name.
  final String name;
}

/// A field of the analyzed class.
class FieldFacts {
  /// Creates facts about the field named [name].
  const FieldFacts({
    required this.name,
    this.isStatic = false,
    this.isFinal = false,
  });

  /// The simple field name.
  final String name;

  /// Whether the field is static.
  final bool isStatic;

  /// Whether the field is final.
  final bool isFinal;

  /// Whether the field name starts with an underscore.
  bool get isPrivate => name.startsWith('_');
}

/// An explicit getter or setter of the analyzed class.
class AccessorFacts {
  /// Creates facts about the accessor named [name].
  const AccessorFacts({
    required this.name,
    required this.isGetter,
    this.isStatic = false,
  });

  /// The simple accessor name.
  final String name;

  /// Whether the accessor is a getter.
  final bool isGetter;

  /// Whether the accessor is static.
  final bool isStatic;

  /// Whether the accessor name starts with an underscore.
  bool get isPrivate => name.startsWith('_');
}

/// The facts about an analyzed class that encapsulation checks depend on.
class ClassFacts {
  /// Creates the facts about a class declaration.
  const ClassFacts({
    required this.name,
    this.supertypeNames = const [],
    this.annotations = const [],
    this.fields = const [],
    this.accessors = const [],
  });

  /// The class name.
  final String name;

  /// Simple names of all direct and indirect supertypes, interfaces, and
  /// mixins.
  final List<String> supertypeNames;

  /// Simple names of the annotations on the class.
  final List<String> annotations;

  /// The fields declared by the class.
  final List<FieldFacts> fields;

  /// The explicit getters and setters declared by the class.
  final List<AccessorFacts> accessors;
}

/// A single encapsulation violation.
class EncapsulationViolation {
  /// Creates a violation of [requirement] on [member].
  const EncapsulationViolation({
    required this.requirement,
    required this.member,
    required this.message,
    required this.severity,
  });

  /// The requirement that was violated, for example `fieldsPrivate`.
  final String requirement;

  /// The member to report on.
  final MemberRef member;

  /// A human-readable description, used as the diagnostic message.
  final String message;

  /// The severity configured for this requirement.
  final RuleSeverity severity;

  @override
  String toString() => message;
}

/// Evaluates class declarations against an [EncapsulationConfig].
///
/// Pure: no analyzer, no file system, no state.
class EncapsulationEvaluator {
  /// Creates an evaluator for [config] that matches paths with [matcher].
  const EncapsulationEvaluator({required this.config, required this.matcher});

  /// The config to evaluate against.
  final EncapsulationConfig config;

  /// The matcher that `files` patterns are matched with.
  final PathMatcher matcher;

  /// All violations for the class described by [facts], declared in [path].
  ///
  /// Every encapsulation that selects the class applies, so one class can be
  /// constrained by more than one.
  List<EncapsulationViolation> evaluateClass({
    required String path,
    required ClassFacts facts,
  }) {
    final violations = <EncapsulationViolation>[];
    for (final encapsulation in config.encapsulations) {
      if (!_selects(encapsulation, path, facts)) continue;
      violations.addAll(_evaluateClass(encapsulation, facts));
    }
    return violations;
  }

  /// Whether [encapsulation] selects the class: its path matches any `files`
  /// pattern, or any selector matches.
  bool _selects(Encapsulation encapsulation, String path, ClassFacts facts) {
    if (encapsulation.files.any((pattern) => matcher.matches(pattern, path))) {
      return true;
    }
    return encapsulation.selectors.any((selector) => _matches(selector, facts));
  }

  bool _matches(ClassSelector selector, ClassFacts facts) => switch (selector) {
    SupertypeSelector(:final name) => facts.supertypeNames.contains(name),
    NameEndsWithSelector(:final suffix) => facts.name.endsWith(suffix),
    NameStartsWithSelector(:final prefix) => facts.name.startsWith(prefix),
    AnnotationSelector(:final name) => facts.annotations.contains(name),
  };

  List<EncapsulationViolation> _evaluateClass(
    Encapsulation encapsulation,
    ClassFacts facts,
  ) {
    EncapsulationViolation violation(
      String requirement,
      MemberRef member,
      String detail,
    ) => EncapsulationViolation(
      requirement: requirement,
      member: member,
      message: '${facts.name}: $detail',
      severity: encapsulation.severityFor(requirement, config.severity),
    );

    final instanceFields = facts.fields
        .where((field) => !field.isStatic)
        .toList();
    final publicGetterNames = {
      for (final accessor in facts.accessors)
        if (accessor.isGetter && !accessor.isStatic && !accessor.isPrivate)
          accessor.name,
    };

    final violations = <EncapsulationViolation>[];

    if (encapsulation.isEnabled(fieldsPrivateRequirement)) {
      for (final field in instanceFields.where((field) => !field.isPrivate)) {
        violations.add(
          violation(
            fieldsPrivateRequirement,
            MemberRef(MemberKind.field, field.name),
            "field '${field.name}' must be private; expose it through a public "
            'getter.',
          ),
        );
      }
    }

    if (encapsulation.isEnabled(privateFieldsFinalRequirement)) {
      for (final field in instanceFields.where(
        (field) => field.isPrivate && !field.isFinal,
      )) {
        violations.add(
          violation(
            privateFieldsFinalRequirement,
            MemberRef(MemberKind.field, field.name),
            "private field '${field.name}' must be final; mutate this state "
            'through methods.',
          ),
        );
      }
    }

    if (encapsulation.isEnabled(noPublicSettersRequirement)) {
      for (final accessor in facts.accessors.where(
        (accessor) => !accessor.isGetter && !accessor.isStatic,
      )) {
        if (accessor.isPrivate) continue;
        violations.add(
          violation(
            noPublicSettersRequirement,
            MemberRef(MemberKind.setter, accessor.name),
            "setter '${accessor.name}' must not be public; expose read-only "
            'state and mutate through methods.',
          ),
        );
      }
    }

    if (encapsulation.isEnabled(requirePublicGettersRequirement)) {
      for (final field in instanceFields.where((field) => field.isPrivate)) {
        final getterName = field.name.substring(1);
        if (!publicGetterNames.contains(getterName)) {
          violations.add(
            violation(
              requirePublicGettersRequirement,
              MemberRef(MemberKind.field, field.name),
              "private field '${field.name}' has no public getter "
              "'$getterName'.",
            ),
          );
        }
      }
    }

    return violations;
  }
}
