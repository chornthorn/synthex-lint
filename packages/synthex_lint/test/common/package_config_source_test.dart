import 'package:synthex_lint/src/common/package_config_source.dart';
import 'package:test/test.dart';

void main() {
  group('sectionWithDefaultSeverity', () {
    test('fills in the document severity', () {
      expect(
        sectionWithDefaultSeverity({
          'version': 1,
          'placements': <Object?>[],
        }, 'error'),
        {'version': 1, 'placements': <Object?>[], 'severity': 'error'},
      );
    });

    test('leaves a section that sets its own severity untouched', () {
      final section = {'severity': 'info', 'version': 1};
      expect(sectionWithDefaultSeverity(section, 'error'), same(section));
    });

    test('leaves the section untouched without a document severity', () {
      final section = {'version': 1};
      expect(sectionWithDefaultSeverity(section, null), same(section));
    });

    test('leaves a section that is not a map untouched', () {
      expect(sectionWithDefaultSeverity('nope', 'error'), 'nope');
    });
  });
}
