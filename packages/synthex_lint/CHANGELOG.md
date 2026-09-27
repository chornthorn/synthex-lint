## 0.1.0 - 2026-09-27

Initial release: an analyzer plugin that ships three schema-driven rules, built
on the official `analysis_server_plugin` API.

- One configuration document for every rule: `synthex_lint.{yaml,yml,json}` in
  the package root, or the `synthex_lint` key of `pubspec.yaml`. A dedicated
  file wins over the pubspec key, and a document key that names no rule section
  and is not `version` or `severity` is reported instead of silently ignored.
  The document sets the `severity` a rule section falls back to.
- `architecture`: layer boundaries and forbidden imports, with severities per
  layer, per check kind (`mayImport` / `forbiddenImports`), and per
  forbidden-import pattern.
- `encapsulation`: conventions for a family of classes selected by file glob,
  supertype, class name, or annotation — private instance fields, final private
  fields, no public setters, a public getter for every private field — with a
  severity per requirement.
- `placement`: where a class lives decides what it is — the name suffix it must
  carry, the supertype it must have or must not have, `exempt` patterns for
  generated code, and a per-placement severity.
- Quick fixes: `AddSupertype` adds the supertype a `placement` violation names,
  appending to the class's `implements` clause or creating it.
- A rule reports under one diagnostic code at every severity, so a single
  `// ignore: <code>` comment covers it however it is configured.
- Rules are declared syntax-only (`canUseParsedResult`), so the plugin analyzes
  the parsed library and keeps reporting while a file does not compile;
  compiled glob patterns are cached.
- The example consumer (`examples/consumer`) enables the plugin and ships
  deliberate violations for every rule.
