/// The `synthex_lint` analyzer plugin.
///
/// This is the entry point the Dart Analysis Server loads: it reads the
/// top-level [plugin] variable and calls [SynthexLintsPlugin.register] to add
/// the plugin's rules and corrections. The package ships three schema-driven
/// rules — `architecture`, `encapsulation`, and `placement` — and each stays
/// inert until the analyzed package configures it, either in a
/// `synthex_lint.yaml`, `.yml`, or `.json` document or under the
/// `synthex_lint` key of its `pubspec.yaml`.
///
/// `main.dart` is the package's only public library; everything under `src/`
/// is implementation detail and not part of the published API.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/common/rule_severity.dart';
import 'src/rules/placement/infrastructure/add_supertype.dart';
import 'src/rules/placement/placement_rule.dart';
import 'src/rules/rule_registry.dart';

/// Entry point loaded by the Dart Analysis Server.
///
/// The server requires a top-level variable named `plugin` in `lib/main.dart`,
/// holding an instance of a `Plugin` subclass.
final plugin = SynthexLintsPlugin();

/// The plugin the Dart Analysis Server runs when a package enables
/// `synthex_lint` in its `analysis_options.yaml`.
///
/// Registration adds every rule in `warningRules` and `lintRules` to the
/// server's registry, plus the `AddSupertype` correction for each diagnostic
/// code the `placement` rule can report under.
class SynthexLintsPlugin extends Plugin {
  /// The plugin's name: the key a package uses under `plugins:` in
  /// `analysis_options.yaml`, and the prefix of a plugin-qualified diagnostic
  /// code such as `synthex_lint/placement`.
  @override
  String get name => 'synthex_lint';

  /// Registers the plugin's rules and corrections with the server.
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
