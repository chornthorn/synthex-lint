import 'package:path/path.dart' as p;

/// The name of the Dart package manifest.
const String pubspecFileName = 'pubspec.yaml';

/// Converts [path] to POSIX form (forward slashes).
///
/// All package-relative paths handled by the domain layer use POSIX
/// separators, independent of the host platform.
String toPosixPath(String path) => path.replaceAll(r'\', '/');

/// The POSIX path of [filePath] relative to [rootPath], or `null` when
/// [filePath] does not live inside [rootPath].
///
/// Rule configuration globs match package-relative paths, so both inputs are
/// normalized to POSIX separators before comparing. The comparison requires a
/// separator after [rootPath], so a sibling such as `/home/app2` is not
/// mistaken for a child of `/home/app`.
String? relativeToRoot({required String filePath, required String rootPath}) {
  final path = toPosixPath(filePath);
  final root = toPosixPath(rootPath);
  if (!path.startsWith('$root/')) return null;
  return path.substring(root.length + 1);
}

/// An import target classified relative to the analyzed package.
sealed class ImportTarget {
  const ImportTarget(this.uri);

  /// The URI exactly as written in the directive.
  final String uri;
}

/// The import points at a file of the analyzed package.
final class InternalImport extends ImportTarget {
  /// Creates an internal import of [uri] at package-relative [path].
  const InternalImport(super.uri, this.path);

  /// Package-relative POSIX path, for example `lib/src/domain/entity.dart`.
  final String path;
}

/// The import points outside the analyzed package (`dart:`, other packages,
/// or a relative URI that escapes the package root).
final class ExternalImport extends ImportTarget {
  /// Creates an external import of [uri].
  const ExternalImport(super.uri);
}

final _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*:');

/// Classifies [uri] as written in an `import` or `export` directive.
///
/// [importingFilePath] is the package-relative POSIX path of the file that
/// contains the directive; [packageName] is the name of the analyzed package
/// (from its `pubspec.yaml`), or `null` when it cannot be determined. With an
/// unknown package name, `package:` self-imports are treated as external.
ImportTarget classifyImport({
  required String uri,
  required String importingFilePath,
  required String? packageName,
}) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return ExternalImport(uri);
    final name = rest.substring(0, slash);
    if (packageName == null || name != packageName) return ExternalImport(uri);
    return InternalImport(
      uri,
      p.url.normalize('lib/${rest.substring(slash + 1)}'),
    );
  }
  if (_schemePattern.hasMatch(uri)) return ExternalImport(uri);

  final target = p.url.normalize(
    p.url.join(p.url.dirname(importingFilePath), uri),
  );
  if (target.startsWith('../')) return ExternalImport(uri);
  return InternalImport(uri, target);
}

final _packageNamePattern = RegExp(
  r'^name:\s*([A-Za-z_][A-Za-z0-9_]*)',
  multiLine: true,
);

/// Extracts the `name:` value from the text of a `pubspec.yaml`, or `null`.
String? parsePackageName(String pubspecYaml) =>
    _packageNamePattern.firstMatch(pubspecYaml)?.group(1);
