import 'package:synthex_lint/src/common/glob_path_matcher.dart';
import 'package:synthex_lint/src/common/package_config_source.dart';
import 'package:synthex_lint/src/common/rule_resolution.dart';
import 'package:synthex_lint/src/rules/architecture/infrastructure/architecture_resolution.dart';
import 'package:synthex_lint/src/rules/encapsulation/infrastructure/encapsulation_resolution.dart';
import 'package:test/test.dart';

void main() {
  final matcher = GlobPathMatcher();
  final source = PackageConfigSource(ruleKey: 'test');

  // Pins the shared contract: every rule's resolution is a `RuleResolution`,
  // carrying the config source and matcher a rule reads its context facts and
  // matches configuration globs with. That is what lets the rule
  // implementations and `reportConfigErrors` work the same way for any rule.
  test('each rule resolution conforms to the shared base', () {
    expect(
      ArchitectureResolution(matcher: matcher, source: source),
      isA<RuleResolution>(),
    );
    expect(
      EncapsulationResolution(matcher: matcher, source: source),
      isA<RuleResolution>(),
    );
  });

  test('the config source and matcher flow through the shared members', () {
    final architecture = ArchitectureResolution(
      matcher: matcher,
      source: source,
      errors: const ['a'],
    );
    expect(architecture.matcher, same(matcher));
    expect(architecture.source, same(source));
    expect(architecture.errors, ['a']);

    final encapsulation = EncapsulationResolution(
      matcher: matcher,
      source: source,
    );
    expect(encapsulation.matcher, same(matcher));
    expect(encapsulation.source, same(source));
    expect(encapsulation.errors, isEmpty);
  });
}
