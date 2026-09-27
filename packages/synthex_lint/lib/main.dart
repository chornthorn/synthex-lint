import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/common/rule_severity.dart';
import 'src/rules/placement/infrastructure/add_supertype.dart';
import 'src/rules/placement/placement_rule.dart';
import 'src/rules/rule_registry.dart';

/// Entry point loaded by the Dart Analysis Server.
///
/// The server requires a top-level variable named `plugin` in `lib/main.dart`.
final plugin = SynthexLintsPlugin();

class SynthexLintsPlugin extends Plugin {
  @override
  String get name => 'synthex_lint';

  @override
  void register(PluginRegistry registry) {
    warningRules.forEach(registry.registerWarningRule);
    lintRules.forEach(registry.registerLintRule);

    // A fix is registered per diagnostic code, and a rule reports under one
    // code per severity, so every severity offers the fix.
    for (final severity in RuleSeverity.values) {
      registry.registerFixForRule(
        PlacementRule.codeFor(severity),
        AddSupertype.new,
      );
    }
  }
}
