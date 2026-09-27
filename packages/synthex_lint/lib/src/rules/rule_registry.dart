import 'package:analyzer/analysis_rule/analysis_rule.dart';

import 'architecture/architecture_rule.dart';
import 'encapsulation/encapsulation_rule.dart';
import 'placement/placement_rule.dart';

/// Rules registered as warnings: enabled by default for every consumer.
final List<AbstractAnalysisRule> warningRules = [];

/// Rules registered as lints: opt-in per project via `analysis_options.yaml`.
final List<AbstractAnalysisRule> lintRules = [
  ArchitectureRule(),
  EncapsulationRule(),
  PlacementRule(),
];
