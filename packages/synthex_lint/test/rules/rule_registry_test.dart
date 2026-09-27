import 'package:synthex_lint/src/common/rule_keys.dart';
import 'package:synthex_lint/src/rules/rule_registry.dart';
import 'package:test/test.dart';

void main() {
  // The config-side key set and the registry are two views of the same thing:
  // every registered rule must accept a config section named after its code,
  // and a document may not name a rule that is not registered.
  test('the config keys match the registered rules', () {
    expect(synthexRuleKeys, {for (final rule in lintRules) rule.name});
  });
}
