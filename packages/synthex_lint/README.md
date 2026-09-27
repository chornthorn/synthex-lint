# synthex_lint

An analyzer plugin that ships synthex's lint rules, built on the official
`analysis_server_plugin` API.

## Requirements

- Dart 3.10+ / Flutter 3.38+ (analyzer plugin support).

## Rules

| Rule            | Default | What it does                                                     |
| --------------- | ------- | ---------------------------------------------------------------- |
| `architecture`  | off     | Enforces layer boundaries; severity per rule.                    |
| `encapsulation` | off     | Enforces that state is private and changes only through methods. |
| `placement`     | off     | Enforces where declarations live and what they are named.        |

## Enable in a project

```yaml
plugins:
  synthex_lint:
    path: ../synthex_lint # local checkout; or `synthex_lint: 0.1.0` once published
    diagnostics:
      architecture: true
      encapsulation: true
      placement: true
```

Then restart the analysis server. Works in the IDE, `dart analyze`, and
`flutter analyze`.

## Config sources

Every rule reads its configuration from **one document** in the analyzed
package:

1. a dedicated file in the package's root, next to `pubspec.yaml`:
   `synthex_lint.yaml`, `.yml`, or `.json`; or
2. the `synthex_lint` key of `pubspec.yaml`.

A dedicated file wins when both are present. The document holds an optional
`version` and `severity` for the plugin as a whole, plus one section per rule,
keyed by the rule's code:

```yaml
# synthex_lint.yaml
version: 1
severity: warning # default for rules that do not set their own
architecture: { ... }
placement: { ... }
encapsulation: { ... }
```

A rule is inert until the document configures it. A broken document, or a
broken section, is reported at `error` severity on every analyzed file, naming
its source — `synthex_lint.yaml 'placement': …`, or
`pubspec.yaml 'synthex_lint.placement': …`. A top-level key that names no rule
section is reported the same way, so a typo cannot silently leave a rule
unconfigured:

```text
synthex_lint.yaml: unknown key 'placementt' (expected a rule section —
architecture, encapsulation, placement — or severity/version).
```

Config is read through the analysis server's file system and cached by
modification stamp, so edits apply without restarting the server.

Each section below is shown at the top level of `synthex_lint.yaml`; inside
`pubspec.yaml` the same sections are nested one level deeper, under
`synthex_lint`.

## The `architecture` rule

The rule declares layers and the imports each layer is allowed to make. A file
that no layer owns is ignored.

```yaml
# synthex_lint.yaml
architecture:
  version: 1
  layers:
    - name: domain
      files: ["lib/src/domain/**"]
      forbiddenImports: [dart:io, package:flutter/**]
    - name: data
      files: ["lib/src/data/**"]
      mayImport: [domain]
    - name: presentation
      files: ["lib/src/presentation/**"]
      mayImport: [domain, data]
```

Sections are YAML or JSON — a `.json` file holds the same document.

Semantics:

- `files` — package-relative glob patterns, for example `lib/src/domain/**`.
  The first layer whose pattern matches a file's path owns that file.
- `mayImport` — names of layers this layer may import. Importing any other
  layer is a violation.
- `forbiddenImports` — URI glob patterns this layer must never import, matched
  against the URI exactly as written (`package:flutter/**`, `dart:io`, ...).
- Both `import` and `export` directives are checked, covering relative URIs,
  self-package URIs, and external packages.
- A broken schema is reported at `error` severity on every analyzed file (see
  [Config sources](#config-sources)). That is deliberately loud: a
  configuration error must not be silent, and the analysis pipeline can run a
  rule several times per file, so "report only once" bookkeeping gets
  swallowed.

### Severity

Every architectural rule can be as strict as the project needs. Set a
severity in the schema; the most specific setting wins:

1. per forbidden-import pattern — `{ uri: dart:io, severity: error }`
2. per check kind in a layer — `severity: { mayImport: error, forbiddenImports: warning }`
3. per layer — `severity: error`
4. schema-wide — `severity: warning`
5. default — `info`

```yaml
# synthex_lint.yaml
architecture:
  version: 1
  severity: warning
  layers:
    - name: domain
      files: ["lib/src/domain/**"]
      severity: error
      forbiddenImports:
        - dart:io
        - uri: package:flutter/**
          severity: info
    - name: data
      files: ["lib/src/data/**"]
      mayImport: [domain]
      severity: { default: warning, mayImport: error }
```

Violations are reported at the configured severity, so `error` fails CI and
`warning` shows up prominently in the IDE. The diagnostic code is always
`architecture`, so a single `// ignore: synthex_lint/architecture` comment
covers every severity.

## The `encapsulation` rule

State is private and changes only through methods. Configured like the other
rules (see [Config sources](#config-sources)) — each entry selects the classes
it governs and declares what they must satisfy:

```yaml
# synthex_lint.yaml
encapsulation:
  version: 1
  severity: error
  encapsulations:
    - files: ["lib/src/presentation/view_models/*"]
      severity: error
      requirements:
        fieldsPrivate: true
        privateFieldsFinal: true
        noPublicSetters: true
```

Every option:

```yaml
# synthex_lint.yaml
encapsulation:
  version: 1
  severity: warning # this rule's default
  encapsulations:
    - files: ["lib/src/presentation/view_models/*"] # package-relative globs
      selectors: # element-based selection, any match selects the class
        - supertype: ChangeNotifier # direct and indirect supertypes, interfaces, mixins
        - nameEndsWith: ViewModel
        - nameStartsWith: ViewModel
        - annotation: viewModel
      requirements: # defaults shown; a map, or a list of entries
        fieldsPrivate: true # instance fields must be private
        privateFieldsFinal: true # private instance fields must be final
        noPublicSetters: true # no public setters
        requirePublicGetters: false # every private field needs a public getter
```

As a list, each entry names one requirement and may carry its settings — the
`enabled` flag and a `severity` that applies to this requirement only:

```yaml
# synthex_lint.yaml
encapsulation:
  version: 1
  severity: warning
  encapsulations:
    - files: ["lib/src/presentation/view_models/*"]
      requirements:
        - fieldsPrivate:
            enabled: true
            severity: warning
        - privateFieldsFinal: false
        - noPublicSetters: true
        - requirePublicGetters: false
```

A requirement an entry does not name keeps its default, and an entry that names
only `severity` leaves the flag as it was. The `severities` map still works and
sets only the severity; when both name the same requirement, the entry wins.

Semantics:

- A class is checked when its path matches any `files` pattern or any selector
  matches. Every encapsulation that selects a class constrains it, so one class
  can be governed by more than one.
- An encapsulation must select something: it needs `files`, `selectors`, or
  both.
- Only instance members are checked; `static` fields and setters are exempt.
- Severity is chosen by the most specific setting: the requirement's own
  `severity` (or the `severities` map), then per encapsulation (`severity`),
  then config-wide.
- Violations carry the class name, for example
  `HomeViewModel: field 'count' must be private`.
- `supertype` matching is element-based — `ChangeNotifier` matches subclasses
  too — so enabling this rule turns off the parsed-results fast path for the
  package.
- A broken config is reported as an error on every analyzed file, naming its
  source (see [Config sources](#config-sources)).

## The `placement` rule

Where a declaration lives decides what it is. Configured like the other rules
(see [Config sources](#config-sources)):

```yaml
# synthex_lint.yaml
placement:
  version: 1
  severity: warning
  placements:
    - files: ["lib/**/view_model/**"]
      classesMustEndWith: [ViewModel, Screen]
      mustHaveSupertype: ChangeNotifier
    - files: ["lib/**/use_cases/**"]
      classesMustEndWith:
        - suffix: UseCase
          exclude: private
      severity: error
    - files: ["lib/**/data/**"]
      classesMustEndWith: Repository
      mustHaveSupertype: Repository
      exempt: ["**/*.g.dart"]
    - files: ["lib/**/presentation/**"]
      mustNotHaveSupertype: Repository
```

Semantics:

- `files` — package-relative glob patterns of the files the placement governs.
  Every placement whose patterns match a file applies, so one class can be
  constrained by more than one placement.
- `exempt` — patterns that opt out of this placement, for example generated
  code.
- `classesMustEndWith` — a suffix, or a list of them; the class name must end
  with any one. An entry can also be a map that pairs the suffix with classes it
  does not apply to: `{suffix: UseCase, exclude: private}` requires the suffix
  of the public classes in a folder and leaves private ones alone. A class
  exempted from one suffix is still checked against the others.
- `mustHaveSupertype` / `mustNotHaveSupertype` — simple names of supertypes the
  class must have, or must not have. Matched against direct and indirect
  supertypes, interfaces, and mixins — the same set `supertype` selectors match
  in the `encapsulation` rule — so `implements` counts.
- Each placement must declare at least one check, and can override the
  config-wide `severity` with its own.
- Only class declarations are checked; mixins, enums, and top-level functions
  are out of scope.
- Supertype matching is element-based, so enabling this rule turns off the
  parsed-results fast path for the package, as `encapsulation` does.
- Violations carry the class name, for example
  `FakeRepository: must extend or implement 'Repository'.`, and are reported on
  the class name.

## Suppressing

```dart
// ignore: synthex_lint/placement
```

Note: the `<plugin>/<code>` prefixed form is effective from Dart 3.12+.
On Dart 3.10/3.11 use the bare form: `// ignore: placement`.

## Quick fixes

One correction ships with the rules, registered in `lib/main.dart`:

| Correction     | Offered when                                                 |
| -------------- | ------------------------------------------------------------ |
| `AddSupertype` | A `placement` violation names exactly one missing supertype. |

`AddSupertype` appends the supertype to the class's `implements` clause,
creating the clause when the class has none:

```dart
class FakeRepository {} // becomes: class FakeRepository implements Repository {}
```

A placement that accepts one of several supertypes
(`mustHaveSupertype: [Repository, DataSource]`) offers no fix: adding one would
be a guess.

Fixes are registered per diagnostic code, and a rule reports under one code per
severity, so `lib/main.dart` registers the fix for all three codes. Corrections
are additive and idempotent — they insert text and leave the rest of the file
alone. `test/support/correction_testing.dart` drives a producer through the
analyzer's own `CorrectionProducerContext`, applies its edits, and returns the
corrected source.

## Adding a rule in 3 steps

1. Copy `lib/src/rules/placement/` — the smallest config-driven rule — and
   rename the folder, the class (`<Code>Rule`), and the `LintCode` name to
   match — rule code == folder name.
   Keep the rule's own folder structure: pure Dart under `<rule>/domain/`,
   analyzer and third-party adapters under `<rule>/infrastructure/`, and the
   rule itself as a thin adapter next to them. Promote a helper to
   `lib/src/common/` only when a second rule needs it.
2. Register it in `lib/src/rules/rule_registry.dart` — under
   `warningRules` (on by default) or `lintRules` (opt-in per project).
3. Add `test/rules/<name>_test.dart` mirroring the reference test, plus a
   demo file in the repo's `examples/consumer/`. A config-driven rule also
   needs a workspace-config test (see `encapsulation_workspace_config_test.dart`)
   proving the config is read from both sources.

## Conventions

- Layering: pure code lives in a `domain/` folder — no analyzer, no
  `dart:io`, no plugin framework; pure utility packages such as `path` and
  `glob` are fine. `<rule>/infrastructure/` implements the domain ports on top
  of the analyzer file system and third-party packages, and the rule itself is
  a thin adapter that translates AST facts into domain calls and reports
  diagnostics.
- `lib/src/common/` holds helpers shared by rules; anything only one rule
  needs stays inside that rule's folder. Unlike `domain/`, a shared helper may
  read through the analyzer's file system — the config loader does — but it
  must never depend on a single rule.
- `test/architecture/domain_purity_test.dart` enforces both: every `domain/`
  folder is pure, and no file in `src/common/` reaches into `src/rules/`; it
  fails the build on either.
- Rules must be stateless — instances are shared by the analysis server, and
  the pipeline may run a rule several times per file.
- A rule's `LintCode` must be a single `static const` field; `// ignore:`
  comments match diagnostics by that code's identity.
- Rule code == folder name. A rule's name is its identity — the diagnostic
  code, the `analysis_options.yaml` entry, the config section, and what
  `// ignore:` matches — so it is defined once in
  `lib/src/common/rule_keys.dart` and every rule takes it from there: the
  `LintCode` names, the `uniqueName`s, `super(name:)`, and the provider's
  `ruleKey` all use the same constant. A rule class is named after its code
  with a `Rule` suffix — `ArchitectureRule`, `EncapsulationRule`,
  `PlacementRule` — so it never collides with the rule's own types
  (`ArchitectureSchema`, `EncapsulationConfig`, …) or with the framework's
  (`RuleProvider`, `RuleResolution`).
- Split the visitor into its own file only when the rule file grows past
  ~120 lines.
- Promote a helper to `src/common/` only when a second rule needs it, with a
  test to match — no speculative abstractions.
- Each config-driven rule keeps one provider under `<rule>/infrastructure/`
  that reads its section of the plugin config document through
  `PackageConfigSource` (`lib/src/common/package_config_source.dart`, given the
  rule's `ruleKey`) and parses it with its own pure parser in `<rule>/domain/`.
  The rule accepts that provider as `RuleProvider<…>`
  (`lib/src/common/rule_provider.dart`): the port is the rule's whole seam, so
  a test injects a resolution without a file system, and there is no per-rule
  provider interface to keep in sync.
- A resolution extends `RuleResolution` (`lib/src/common/rule_resolution.dart`)
  and carries the config source (`PackageConfigSource`), the matcher, and the
  configuration errors found; the subclass adds its rule's typed configuration
  (`schema`, `config`, …). `reportConfigErrors` reports the errors for any
  rule, so a broken configuration is never silent, and a rule implementation
  reads the analyzed file's path and package name through `resolution.source`
  — the provider is the only place that touches the analysis context for them.
- Corrections — quick fixes, and quick assists if one is ever added — live
  under `<rule>/infrastructure/` and are registered in `lib/main.dart`: a fix
  per diagnostic code, an assist once. A producer works from `node`, as the
  plugin docs' own examples do: it is the node covering the diagnostic for a
  fix, and the node covering the selection for an assist, while `coveringNode`
  is `null` whenever there is no diagnostic and so cannot serve an assist. A
  correction must be additive, must leave the file compiling, and must produce
  no edit rather than guess.
- Never rename a diagnostic code without a CHANGELOG note; users' ignore
  comments reference it.

## Performance

The `architecture` rule is syntax-only and declares `canUseParsedResult`, so
the plugin server does not force a resolved unit for a file where every enabled
rule is syntax-only: it analyzes the parsed library instead. That keeps the
plugin cheap on large projects and lets it report diagnostics while a file does
not compile. The `encapsulation` and `placement` rules match supertypes, which
needs resolved elements, so enabling either turns that fast path off for the
package.

Pattern matching compiles each glob once and caches it: the architecture
rule matches every import of every file against every layer pattern, so
re-parsing globs per match used to dominate the rule's CPU time.

`benchmark/architecture_evaluator.dart` measures the pure evaluation path:

```sh
dart run benchmark/architecture_evaluator.dart
```

## Dev-loop notes

- `print()` does not reach the console in plugins (they run in a separate
  isolate) — log to a file instead.
- Restart the analysis server after changing plugin code.
- `lib/main.dart` is the entry point the server loads, so it cannot be renamed
  to match the package name; `dart pub publish --dry-run` reports that as a
  style hint, along with a "checked-in files are modified" warning until the
  working tree is committed. Both are expected.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
