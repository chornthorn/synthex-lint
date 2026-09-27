import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Decodes a rule configuration document.
///
/// Files ending in `.yaml` or `.yml` are decoded as YAML, everything else as
/// JSON. Returns `null` for an empty document.
///
/// Throws [FormatException] for invalid JSON and [YamlException] for invalid
/// YAML; callers turn those into user-facing configuration errors.
Object? decodeConfigDocument(String content, {required String path}) {
  final lowerCasePath = path.toLowerCase();
  if (lowerCasePath.endsWith('.yaml') || lowerCasePath.endsWith('.yml')) {
    return loadYaml(content);
  }
  return jsonDecode(content);
}
