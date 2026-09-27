/// The identity of each rule, defined once.
///
/// A rule's name is its identity in every sense the plugin has: the diagnostic
/// code users see, the `analysis_options.yaml` entry that enables it, the
/// section key it reads from the config document, and the name an
/// `// ignore:` comment matches. Each rule therefore takes its name from here
/// instead of repeating the string, and [synthexRuleKeys] is built from the
/// same constants.
library;

/// The name of the architecture rule.
const String architectureRuleName = 'architecture';

/// The name of the encapsulation rule.
const String encapsulationRuleName = 'encapsulation';

/// The name of the placement rule.
const String placementRuleName = 'placement';

/// Document-level keys, next to the rule sections.
const Set<String> synthexDocumentKeys = {'version', 'severity'};

/// The rule keys a document may hold a section for.
///
/// `test/rules/rule_registry_test.dart` fails when this set and the registered
/// rules drift apart, in either direction: a key without a rule, or a rule
/// without a key.
const Set<String> synthexRuleKeys = {
  architectureRuleName,
  encapsulationRuleName,
  placementRuleName,
};
