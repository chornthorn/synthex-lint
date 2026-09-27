import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../domain/required_supertype.dart';

/// Adds the supertype a placement requires.
///
/// A class in a governed folder must implement the layer's contract, so the
/// correction inserts it into the class's `implements` clause — creating the
/// clause when the class has none. It is only offered when the violation names
/// exactly one supertype: with several, adding one would be a guess.
class AddSupertype extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'synthex_lint.fix.addSupertype',
    DartFixKindPriority.standard,
    'Add the required supertype',
  );

  AddSupertype({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final message = diagnostic?.problemMessage.messageText(includeUrl: false);
    if (message == null) return;
    final supertype = requiredSupertypeFrom(message);
    if (supertype == null) return;

    final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
    if (declaration == null) return;

    final implementsClause = declaration.implementsClause;
    await builder.addDartFileEdit(file, (builder) {
      if (implementsClause != null) {
        builder.addInsertion(
          implementsClause.end,
          (builder) => builder.write(', $supertype'),
        );
      } else {
        builder.addInsertion(
          declaration.namePart.end,
          (builder) => builder.write(' implements $supertype'),
        );
      }
    });
  }
}
