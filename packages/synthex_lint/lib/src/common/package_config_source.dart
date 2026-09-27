import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'config_document.dart';
import 'package_paths.dart';
import 'rule_keys.dart';

/// The config file names, in priority order.
///
/// One document holds the configuration of every rule, in a section per rule
/// key, so a package configures the plugin once.
const List<String> synthexConfigFileNames = [
  'synthex_lint.yaml',
  'synthex_lint.yml',
  'synthex_lint.json',
];

/// The `pubspec.yaml` key that can hold the configuration instead of a
/// dedicated file.
const String synthexConfigPubspecKey = 'synthex_lint';

/// The document format version understood by this package.
const int synthexConfigVersion = 1;

/// The rule sections a document may hold, sorted, for error messages.
final List<String> _expectedSections = synthexRuleKeys.toList()..sort();

/// The document-level keys, sorted, for error messages.
final List<String> _expectedDocumentKeys = synthexDocumentKeys.toList()..sort();

/// A decoded rule configuration document and where it came from.
class ConfigDocument {
  const ConfigDocument({this.document, required this.source, this.error});

  /// The decoded document — a `Map` for a well-formed config — or `null` when
  /// [error] is set.
  final Object? document;

  /// A read or decode error for a configured but unreadable document.
  final String? error;

  /// Where the document came from, for error messages, for example
  /// `synthex_lint.yaml 'placement'` or
  /// `pubspec.yaml 'synthex_lint.placement'`.
  final String source;
}

/// The section of [document] for one rule, with the document's `severity`
/// filled in when the section does not set its own.
///
/// A document can therefore set one severity for every rule, and a rule section
/// that wants a different one overrides it. Everything else about the section
/// is left untouched.
Object? sectionWithDefaultSeverity(Object? section, Object? documentSeverity) {
  if (documentSeverity == null) return section;
  if (section is! Map) return section;
  if (section.containsKey('severity')) return section;
  return {...section, 'severity': documentSeverity};
}

/// Locates and decodes the plugin's configuration document for the analyzed
/// package, and extracts one rule's section from it.
///
/// The dedicated file wins: the first existing candidate in
/// [synthexConfigFileNames] is used; otherwise the [synthexConfigPubspecKey]
/// entry of `pubspec.yaml` is used. When neither exists, there is no
/// configuration and the calling rule stays inert.
///
/// A document carries an optional `version` and `severity` for the whole
/// plugin, and one section per rule keyed by the rule's code:
///
/// ```yaml
/// version: 1
/// severity: warning
/// placement: { ... }
/// encapsulation: { ... }
/// ```
///
/// Reads go through the analyzer's file system, so this works for IDE
/// overlays, virtual test file systems, and real files alike. Results are
/// cached per file path and invalidated by modification stamp, so edits are
/// picked up without restarting the analysis server.
class PackageConfigSource {
  PackageConfigSource({required this.ruleKey});

  /// The key of the rule's section inside the document — the rule's code.
  final String ruleKey;

  final Map<String, _Entry<ConfigDocument>> _documents = {};
  final Map<String, _Entry<String?>> _packageNames = {};

  /// The configuration section for [ruleKey], or `null` when the package
  /// configures neither the plugin nor this rule.
  ConfigDocument? config(RuleContext context) {
    final package = context.package;
    if (package == null) return null;
    final root = package.root;

    for (final fileName in synthexConfigFileNames) {
      final resource = root.getChild(fileName);
      if (resource is! File || !resource.exists) continue;
      return _section(
        _cache<ConfigDocument>(
          resource,
          _documents,
          () => _decode(resource, source: fileName),
        ),
        documentSource: fileName,
        sectionPath: ruleKey,
      );
    }

    final pubspec = root.getChild(pubspecFileName);
    if (pubspec is! File || !pubspec.exists) return null;
    final pubspecDocument = _cache<ConfigDocument>(
      pubspec,
      _documents,
      () => _decode(pubspec, source: pubspecFileName),
    );
    if (pubspecDocument.error != null) return pubspecDocument;
    if (pubspecDocument.document case final Map pubspecMap) {
      final document = pubspecMap[synthexConfigPubspecKey];
      if (document == null) return null;
      return _section(
        ConfigDocument(document: document, source: pubspecFileName),
        documentSource: pubspecFileName,
        sectionPath: '$synthexConfigPubspecKey.$ruleKey',
      );
    }
    return null;
  }

  /// The `name` from the package's manifest, or `null`.
  String? packageName(RuleContext context) {
    final package = context.package;
    if (package == null) return null;
    final resource = package.root.getChild(pubspecFileName);
    if (resource is! File || !resource.exists) return null;
    return _cache<String?>(
      resource,
      _packageNames,
      () => parsePackageName(resource.readAsStringSync()),
    );
  }

  /// The package-relative POSIX path of the unit currently being analyzed, or
  /// `null` when the unit cannot be located inside its package.
  ///
  /// A rule reaches this through the resolution's source
  /// (`RuleResolution.source`), so a glob such as `lib/src/domain/**` is
  /// matched against the same path in every rule. The path math itself is
  /// [relativeToRoot]; nothing is read from disk, so unlike [config] this is
  /// not cached.
  String? packageRelativePath(RuleContext context) {
    final unit = context.currentUnit;
    final package = context.package;
    if (unit == null || package == null) return null;
    return relativeToRoot(
      filePath: unit.file.path,
      rootPath: package.root.path,
    );
  }

  /// The section for [ruleKey] inside [document], or `null` when the document
  /// does not configure this rule.
  ConfigDocument? _section(
    ConfigDocument document, {
    required String documentSource,
    required String sectionPath,
  }) {
    if (document.error != null) return document;
    final root = document.document;
    if (root is! Map) {
      return ConfigDocument(source: documentSource, document: root);
    }
    final version = root['version'];
    if (version != null &&
        (version is! num || version != synthexConfigVersion)) {
      return ConfigDocument(
        source: documentSource,
        error:
            'Unsupported version: $version (expected $synthexConfigVersion).',
      );
    }
    // A key nobody reads is a typo, and a typo would silently leave a rule
    // inert: report it instead of ignoring it.
    final unknownKeys =
        root.keys
            .whereType<String>()
            .where(
              (key) =>
                  !synthexDocumentKeys.contains(key) &&
                  !synthexRuleKeys.contains(key),
            )
            .toList()
          ..sort();
    if (unknownKeys.isNotEmpty) {
      final quoted = unknownKeys.map((key) => "'$key'").join(', ');
      return ConfigDocument(
        source: documentSource,
        error:
            '$documentSource: unknown key${unknownKeys.length > 1 ? 's' : ''} '
            '$quoted (expected a rule section — ${_expectedSections.join(', ')} '
            '— or ${_expectedDocumentKeys.join('/')}).',
      );
    }
    final section = root[ruleKey];
    if (section == null) return null;
    return ConfigDocument(
      document: sectionWithDefaultSeverity(section, root['severity']),
      source: "$documentSource '$sectionPath'",
    );
  }

  ConfigDocument _decode(File file, {required String source}) {
    final String content;
    try {
      content = file.readAsStringSync();
    } on Exception catch (error) {
      return ConfigDocument(
        source: source,
        error: '$source could not be read: $error',
      );
    }
    try {
      return ConfigDocument(
        document: decodeConfigDocument(content, path: file.path),
        source: source,
      );
    } on FormatException catch (error) {
      // `YamlException` is a subtype of `FormatException`, so this covers
      // both invalid JSON and invalid YAML.
      return ConfigDocument(
        source: source,
        error: '$source is not valid: ${error.message}',
      );
    }
  }

  /// Cache maps are declared with the exact type used at their call sites,
  /// which is why each call passes `T` explicitly: relying on inference here
  /// would let the covariant generic type system insert an entry of the wrong
  /// runtime type and fail later, inside the map.
  T _cache<T>(File file, Map<String, _Entry<T>> cache, T Function() build) {
    final stamp = file.modificationStamp;
    final cached = cache[file.path];
    if (cached != null && cached.stamp == stamp) return cached.value;
    final entry = _Entry<T>(stamp: stamp, value: build());
    cache[file.path] = entry;
    return entry.value;
  }
}

class _Entry<T> {
  _Entry({required this.stamp, required this.value});

  final int stamp;
  final T value;
}
