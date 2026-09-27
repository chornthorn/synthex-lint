import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:synthex_lint/src/common/rule_keys.dart';
import 'package:synthex_lint/src/common/rule_provider.dart';
import 'package:synthex_lint/src/rules/architecture/architecture_rule.dart';
import 'package:synthex_lint/src/rules/architecture/infrastructure/architecture_resolution.dart';
import 'package:synthex_lint/src/rules/encapsulation/encapsulation_rule.dart';
import 'package:synthex_lint/src/rules/encapsulation/infrastructure/encapsulation_resolution.dart';
import 'package:test/test.dart';

/// A provider that knows nothing but the shared port — no rule-specific
/// interface, no file system.
class _InertArchitectureProvider
    implements RuleProvider<ArchitectureResolution> {
  @override
  ArchitectureResolution? resolve(RuleContext context) => null;
}

class _InertEncapsulationProvider
    implements RuleProvider<EncapsulationResolution> {
  @override
  EncapsulationResolution? resolve(RuleContext context) => null;
}

void main() {
  // Pins the shared contract: a rule is wired through `RuleProvider<…>` alone,
  // so any provider — the production one, or a test double that never touches
  // the file system — satisfies the rule's whole seam.
  test('a bare port implementer wires into a rule', () {
    expect(
      ArchitectureRule(provider: _InertArchitectureProvider()).name,
      architectureRuleName,
    );
    expect(
      EncapsulationRule(provider: _InertEncapsulationProvider()).name,
      encapsulationRuleName,
    );
  });

  test('the production providers implement the same port', () {
    expect(ArchitectureProvider(), isA<RuleProvider<ArchitectureResolution>>());
    expect(
      EncapsulationProvider(),
      isA<RuleProvider<EncapsulationResolution>>(),
    );
  });
}
