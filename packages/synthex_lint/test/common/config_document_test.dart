import 'package:synthex_lint/src/common/config_document.dart';
import 'package:test/test.dart';

void main() {
  group('decodeConfigDocument', () {
    test('decodes JSON when the path is not a YAML file', () {
      expect(decodeConfigDocument('{"version": 1}', path: 'config.json'), {
        'version': 1,
      });
    });

    test('decodes .yaml content as YAML', () {
      final document = decodeConfigDocument('version: 1', path: 'config.yaml');
      expect(document, isA<Map>());
      expect((document! as Map)['version'], 1);
    });

    test('decodes .yml content as YAML', () {
      final document = decodeConfigDocument('version: 1', path: 'config.yml');
      expect((document! as Map)['version'], 1);
    });

    test('recognizes the YAML extension case-insensitively', () {
      final document = decodeConfigDocument('version: 1', path: 'CONFIG.YAML');
      expect((document! as Map)['version'], 1);
    });

    test('throws a FormatException for invalid JSON', () {
      expect(
        () => decodeConfigDocument('{', path: 'config.json'),
        throwsFormatException,
      );
    });

    test('throws a FormatException for invalid YAML', () {
      // `YamlException` is a `FormatException`, which is what callers catch.
      expect(
        () => decodeConfigDocument('key: [', path: 'config.yaml'),
        throwsFormatException,
      );
    });
  });
}
