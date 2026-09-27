import 'package:analysis_server_plugin/src/correction/fix_generators.dart';
import 'package:analysis_server_plugin/src/registry.dart';
import 'package:synthex_lint/main.dart';
import 'package:synthex_lint/src/common/rule_severity.dart';
import 'package:synthex_lint/src/rules/placement/infrastructure/add_supertype.dart';
import 'package:synthex_lint/src/rules/placement/placement_rule.dart';
import 'package:test/test.dart';

/// Guards the entry point the analysis server loads.
///
/// A correction that is not registered is silently never offered, and the IDE
/// shows nothing to explain why — so the wiring itself is asserted here rather
/// than reviewed.
void main() {
  setUp(() {
    final registry = PluginRegistryImpl('synthex_lint');
    SynthexLintsPlugin().register(registry);
  });

  test('registers the supertype fix for all of its severity codes', () {
    for (final severity in RuleSeverity.values) {
      expect(
        registeredFixGenerators.lintProducers[PlacementRule.codeFor(severity)],
        contains(AddSupertype.new),
        reason: 'the supertype fix answers the $severity placement code',
      );
    }
  });
}
