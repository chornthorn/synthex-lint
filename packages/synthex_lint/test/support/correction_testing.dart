import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';

/// Creates a correction producer — a fix or an assist — for a context.
typedef CorrectionFactory =
    ResolvedCorrectionProducer Function({
      required CorrectionProducerContext context,
    });

/// Runs a correction producer and returns the source it produces.
///
/// [offset] and [length] are the selection the correction is computed for — the
/// diagnostic's range for a fix, or the code the developer selected for an
/// assist. The edits are applied to [result]'s content, so a test can assert
/// the corrected source directly.
Future<String> applyCorrection({
  required ResolvedUnitResult result,
  required int offset,
  required int length,
  required CorrectionFactory create,
  Diagnostic? diagnostic,
}) async {
  final libraryResult = await result.session.getResolvedLibrary(result.path);
  if (libraryResult is! ResolvedLibraryResult) {
    throw StateError('${result.path} does not resolve to a library');
  }
  final context = CorrectionProducerContext.createResolved(
    libraryResult: libraryResult,
    unitResult: result,
    diagnostic: diagnostic,
    selectionOffset: offset,
    selectionLength: length,
  );
  final builder = ChangeBuilder(session: result.session);
  await create(context: context).compute(builder);
  return _apply(result.content, builder.sourceChange);
}

/// Runs the correction registered for [code] on the diagnostic reported at
/// [offset].
Future<String> applyFix({
  required ResolvedUnitResult result,
  required String code,
  required int offset,
  required CorrectionFactory create,
}) {
  final diagnostic = result.diagnostics.firstWhere(
    (diagnostic) =>
        diagnostic.diagnosticCode.lowerCaseName == code &&
        diagnostic.problemMessage.offset == offset,
    orElse: () => throw StateError(
      'no $code diagnostic at offset $offset in ${result.path}',
    ),
  );
  return applyCorrection(
    result: result,
    offset: diagnostic.problemMessage.offset,
    length: diagnostic.problemMessage.length,
    diagnostic: diagnostic,
    create: create,
  );
}

/// Applies [change] to [source], last edit first so earlier offsets stay valid.
String _apply(String source, SourceChange change) {
  final edits = [
    for (final fileEdit in change.edits)
      for (final edit in fileEdit.edits) edit,
  ]..sort((first, second) => second.offset.compareTo(first.offset));
  var result = source;
  for (final edit in edits) {
    result = result.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      edit.replacement,
    );
  }
  return result;
}
