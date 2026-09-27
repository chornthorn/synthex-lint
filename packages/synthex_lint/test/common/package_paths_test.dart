import 'package:synthex_lint/src/common/package_paths.dart';
import 'package:test/test.dart';

void main() {
  group('classifyImport', () {
    test('resolves relative imports against the importing file', () {
      final target = classifyImport(
        uri: '../data/repo.dart',
        importingFilePath: 'lib/src/domain/entity.dart',
        packageName: 'app',
      );

      expect(target, isA<InternalImport>());
      expect((target as InternalImport).path, 'lib/src/data/repo.dart');
    });

    test('resolves self package imports to a lib/ path', () {
      final target = classifyImport(
        uri: 'package:app/src/data/repo.dart',
        importingFilePath: 'lib/src/domain/entity.dart',
        packageName: 'app',
      );

      expect(target, isA<InternalImport>());
      expect((target as InternalImport).path, 'lib/src/data/repo.dart');
    });

    test('treats other packages as external', () {
      final target = classifyImport(
        uri: 'package:collection/collection.dart',
        importingFilePath: 'lib/src/domain/entity.dart',
        packageName: 'app',
      );

      expect(target, isA<ExternalImport>());
    });

    test('treats dart: imports as external', () {
      final target = classifyImport(
        uri: 'dart:io',
        importingFilePath: 'lib/main.dart',
        packageName: 'app',
      );

      expect(target, isA<ExternalImport>());
    });

    test('treats relative imports escaping the package as external', () {
      final target = classifyImport(
        uri: '../../outside.dart',
        importingFilePath: 'lib/a.dart',
        packageName: 'app',
      );

      expect(target, isA<ExternalImport>());
    });

    test(
      'treats self imports as external when the package name is unknown',
      () {
        final target = classifyImport(
          uri: 'package:app/src/data/repo.dart',
          importingFilePath: 'lib/src/domain/entity.dart',
          packageName: null,
        );

        expect(target, isA<ExternalImport>());
      },
    );

    test('treats package URIs without a path as external', () {
      final target = classifyImport(
        uri: 'package:app',
        importingFilePath: 'lib/main.dart',
        packageName: 'app',
      );

      expect(target, isA<ExternalImport>());
    });
  });

  group('relativeToRoot', () {
    test('strips the root prefix', () {
      expect(
        relativeToRoot(
          filePath: '/home/app/lib/main.dart',
          rootPath: '/home/app',
        ),
        'lib/main.dart',
      );
    });

    test('keeps nested paths intact', () {
      expect(
        relativeToRoot(
          filePath: '/home/app/lib/src/domain/entity.dart',
          rootPath: '/home/app',
        ),
        'lib/src/domain/entity.dart',
      );
    });

    test('normalizes Windows separators', () {
      expect(
        relativeToRoot(filePath: r'C:\app\lib\main.dart', rootPath: r'C:\app'),
        'lib/main.dart',
      );
    });

    test('returns null for a file outside the root', () {
      expect(
        relativeToRoot(
          filePath: '/home/other/lib/main.dart',
          rootPath: '/home/app',
        ),
        isNull,
      );
    });

    test('returns null for a sibling sharing the root prefix', () {
      expect(
        relativeToRoot(
          filePath: '/home/app2/lib/main.dart',
          rootPath: '/home/app',
        ),
        isNull,
      );
    });

    test('returns null when the path is the root itself', () {
      expect(
        relativeToRoot(filePath: '/home/app', rootPath: '/home/app'),
        isNull,
      );
    });
  });

  group('parsePackageName', () {
    test('reads the name', () {
      expect(parsePackageName('name: my_app\nversion: 1.0.0'), 'my_app');
    });

    test('ignores commented out names', () {
      expect(parsePackageName('# name: nope\nname: real_app'), 'real_app');
    });

    test('returns null when there is no name', () {
      expect(parsePackageName('version: 1.0.0'), isNull);
    });
  });
}
