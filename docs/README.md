# synthex-lint documentation

Complete documentation for the `synthex-lint` repository: an analyzer plugin for
Dart and Flutter that ships schema-driven architecture and convention rules, plus
the example package that demonstrates them.

The package README ([`packages/synthex_lint/README.md`](../packages/synthex_lint/README.md))
is the pub.dev-facing quick reference; this document is the full guide.

- [Overview](#overview)
- [Quickstart](#quickstart)
- [How the plugin works](#how-the-plugin-works)
- [Configuration](#configuration)
- [The `architecture` rule](#the-architecture-rule)
- [The `encapsulation` rule](#the-encapsulation-rule)
- [The `placement` rule](#the-placement-rule)
- [A complete configuration](#a-complete-configuration)
- [Diagnostics, suppression, and quick fixes](#diagnostics-suppression-and-quick-fixes)
- [Troubleshooting](#troubleshooting)
- [Codebase architecture](#codebase-architecture)
- [Development](#development)
- [Publishing to pub.dev](#publishing-to-pubdev)
- [License](#license)

## Overview

This repository contains one published package and one example:

| Path                                                | What it is                                                                |
| --------------------------------------------------- | ------------------------------------------------------------------------- |
| [`packages/synthex_lint`](../packages/synthex_lint) | The analyzer plugin: schema-driven architecture rules and other lints.    |
| [`examples/consumer`](../examples/consumer)         | Example package that enables the plugin and demonstrates its diagnostics. |

The plugin is built on the official `analysis_server_plugin` API and works in
the IDE, `dart analyze`, and `flutter analyze`.

### Requirements

- Dart 3.10+ or Flutter 3.38+ (analyzer plugin support).
- Suppression syntax: the `<plugin>/<code>` prefixed ignore form
  (`// ignore: synthex_lint/placement`) is effective from Dart 3.12+. On Dart
  3.10 and 3.11 use the bare form (`// ignore: placement`).

### Rules

| Rule            | Default | What it enforces                                                                                                    |
| --------------- | ------- | ------------------------------------------------------------------------------------------------------------------- |
| `architecture`  | off     | Layer boundaries and forbidden imports: which layer may import which, and which URIs are banned.                    |
| `encapsulation` | off     | State conventions for a family of classes: private fields, final private fields, no public setters, public getters. |
| `placement`     | off     | Where a declaration lives decides what it is: required name suffixes and supertypes per folder.                     |

Everything a rule needs comes from one configuration document in the analyzed
package. A rule is inert until the document configures it, and a broken
configuration is reported loudly instead of being silently ignored.

## Quickstart

### Enable the plugin in a package

1. Declare the plugin in the package's `analysis_options.yaml`:

```yaml
# analysis_options.yaml
plugins:
  synthex_lint:
    path: ../synthex_lint # a local checkout; or `synthex_lint: ^0.1.0` once published
    diagnostics:
      architecture: true
      encapsulation: true
      placement: true
```

The analysis server resolves enabled plugins into a synthetic package of its
own, so the analyzed package does not need `synthex_lint` as a dependency to
load it. (The example consumer lists it as a dev dependency as well; that
listing is not what makes the plugin load.) Plugin lint rules are opt-in: a rule
that is not listed under `diagnostics`, or is listed as `false`, is not enabled.

2. Add a configuration document at the package root, next to `pubspec.yaml`:

```yaml
# synthex_lint.yaml
version: 1
severity: warning
placement:
  version: 1
  placements:
    - files: ["lib/**/view_models/**"]
      classesMustEndWith: ViewModel
```

3. Restart the analysis server. The server must be restarted after any change
   to the `plugins` section of `analysis_options.yaml`; after that, run
   `dart analyze` (or `flutter analyze`), or watch the IDE.

Enabling a diagnostic and configuring it are two separate steps: a rule listed
under `diagnostics` stays inert until the document holds a section for it.

### Try the example

```sh
cd examples/consumer
dart pub get
dart analyze
```

The example ships deliberate violations, so `dart analyze` exits non-zero by
design and prints two diagnostics:

```text
warning • lib/data/repository.dart:9:7 • FakeRepository: must extend or implement 'Repository'. • placement
warning • lib/domain/use_cases/get_user_usecase.dart:3:7 • The declaration '_Demo' isn't referenced. Try removing the declaration of '_Demo'. • unused_element
```

The first is the plugin's `placement` rule; the second is the analyzer's own
`unused_element` warning for a class that demonstrates the private-class
exemption. The [example README](../examples/consumer/README.md) explains where
each comes from.

### Work on the plugin

```sh
cd packages/synthex_lint
dart pub get
dart test
```

## How the plugin works

### Entry point and registration

The analysis server loads `lib/main.dart`, reads the top-level `plugin`
variable, and calls `SynthexLintsPlugin.register`. Registration adds:

- the rules in `warningRules` as warnings — enabled by default for every
  consumer;
- the rules in `lintRules` as lints — opt-in per project through the
  `diagnostics:` section;
- the `AddSupertype` correction for each diagnostic code the `placement` rule
  can report under, so the fix is offered at every severity.

All three rules currently ship as lint rules.

### Rule anatomy

Every config-driven rule is a thin adapter over a pure evaluator:

```text
lib/src/rules/<rule>/
├── <rule>_rule.dart      the rule: AST facts → domain calls → diagnostics
├── domain/               pure Dart: config model, parser, evaluator
└── infrastructure/       analyzer and third-party adapters: provider, resolution, corrections
```

- The **provider** implements `RuleProvider<Resolution>`. It reads the rule's
  section of the config document through `PackageConfigSource` and parses it
  with the rule's pure parser. This port is the rule's whole seam.
- The **resolution** carries the parsed configuration, the pattern matcher, the
  config source, and any configuration errors worth reporting.
- The **evaluator** is pure: no analyzer, no file system, no state. Rule tests
  inject a fixed resolution, so they run without a file system.
- The **rule adapter** translates AST facts into evaluator calls and reports
  each violation under the diagnostic code for its severity.

`lib/src/common/` holds helpers shared by rules — the config source, the
matcher, the severity parser, the resolution base class. A helper is promoted
there only when a second rule needs it.

### Reading configuration

`PackageConfigSource` reads the document through the analyzer's file system, so
IDE overlays, virtual test file systems, and real files all work, and caches it
per file path by modification stamp. Editing the document takes effect without
restarting the analysis server; editing the `plugins` section does not.

### Reporting while a file does not compile

The `architecture` rule is syntax-only and declares `canUseParsedResult`, so the
server does not have to force a resolved unit for a file where every enabled
rule is syntax-only: it analyzes the parsed library instead. That keeps the
plugin cheap on large projects and lets the rule keep reporting while a file
does not compile. The `encapsulation` and `placement` rules match supertypes,
which needs resolved elements, so enabling either turns that fast path off for
the package.

### Rule identity

A rule's name is its identity everywhere: the diagnostic code, the
`diagnostics:` entry, the config section key, and what `// ignore:` matches.
Each name is defined once in `lib/src/common/rule_keys.dart`. Rule code ==
folder name, and the rule class is named after its code with a `Rule` suffix
(`ArchitectureRule`, `EncapsulationRule`, `PlacementRule`).

## Configuration

### Sources and precedence

Every rule reads its configuration from **one document** in the analyzed
package:

1. a dedicated file in the package root, next to `pubspec.yaml`:
   `synthex_lint.yaml`, `synthex_lint.yml`, or `synthex_lint.json`, in that
   priority order; or
2. the `synthex_lint` key of `pubspec.yaml`.

A dedicated file wins when both are present. When neither exists, there is no
configuration and every rule stays inert.

The document holds an optional `version` and `severity` for the plugin as a
whole, plus one section per rule, keyed by the rule's code:

```yaml
# synthex_lint.yaml
version: 1
severity: warning # default for rules that do not set their own
architecture: { ... }
encapsulation: { ... }
placement: { ... }
```

Inside `pubspec.yaml` the same sections are nested one level deeper, under
`synthex_lint`:

```yaml
# pubspec.yaml
synthex_lint:
  version: 1
  severity: warning
  placement: { ... }
```

A `.json` file holds the same document; only the syntax differs.

### Validation and error reporting

- `version` must be `1` when present. Each rule section also carries its own
  optional `version`, also checked against `1`.
- A top-level key that names no rule section and is not `version` or `severity`
  is reported instead of silently ignored, so a typo cannot leave a rule
  unconfigured:

  ```text
  synthex_lint.yaml: unknown key 'placementt' (expected a rule section —
  architecture, encapsulation, placement — or severity/version).
  ```

- A document that cannot be read or decoded is reported:

  ```text
  synthex_lint.yaml could not be read: <error>
  synthex_lint.yaml is not valid: <parse error>
  ```

- A section that fails its own schema reports every problem it found, rather
  than stopping at the first:

  ```text
  synthex_lint.yaml 'placement': 'placements' must be a non-empty list.
  ```

Configuration errors are reported at `error` severity at the top of **every
analyzed file**, naming their source — `synthex_lint.yaml 'placement': …`, or
`pubspec.yaml 'synthex_lint.placement': …`. That is deliberately loud: a
configuration error must not be silent, and the analysis pipeline can run a
rule several times per file, so "report only once" bookkeeping gets swallowed.

### Severity

A violation can be reported as `info`, `warning`, or `error`. `error` fails CI,
`warning` shows up prominently in the IDE, `info` is unobtrusive. A rule section
falls back to the document-level `severity` when it does not set its own, and to
`info` when neither does.

Each rule picks the severity from the most specific setting that applies:

| Rule            | Most specific → least specific                                                              |
| --------------- | ------------------------------------------------------------------------------------------- |
| `architecture`  | per forbidden-import pattern → per check kind in a layer → per layer → schema-wide → `info` |
| `encapsulation` | requirement's own `severity` → `severities` map → per encapsulation → config-wide → `info`  |
| `placement`     | per placement → config-wide → `info`                                                        |

The diagnostic code is always the rule's name — `architecture`,
`encapsulation`, or `placement` — at every severity, so a single
`// ignore: synthex_lint/placement` comment covers the rule however it is
configured.

### Patterns and paths

Rule configuration globs match **package-relative POSIX paths**, for example
`lib/src/domain/**`. The path is the analyzed file's path relative to the
package root (the directory holding `pubspec.yaml`). Patterns must be relative
to the package root — a leading `/` is a configuration error — and must compile
as globs; a pattern that does not compile is reported instead of silently
matching nothing.

Patterns without wildcards are compared for exact equality, which is what makes
URI patterns such as `dart:io` work without escaping. Import URI patterns are
matched against the URI exactly as written in the directive.

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

### Section reference

| Key        | Type     | Required | Meaning                                                           |
| ---------- | -------- | -------- | ----------------------------------------------------------------- |
| `version`  | int      | no       | Must be `1` when present.                                         |
| `severity` | severity | no       | Schema-wide default for violations. Falls back to the document's. |
| `layers`   | list     | yes      | A non-empty list of layers, in declaration order.                 |

### Layer reference

| Key                | Type                                                 | Required | Meaning                                                                                                |
| ------------------ | ---------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `name`             | string                                               | yes      | The layer's name; unique, and referenced by other layers' `mayImport`.                                 |
| `files`            | glob or list of globs                                | yes      | Package-relative patterns of this layer's files. The first layer whose pattern matches a path owns it. |
| `mayImport`        | list of layer names                                  | no       | Layers this layer may import. Importing any other layer is a violation.                                |
| `forbiddenImports` | list of URI patterns or `{uri, severity}` objects    | no       | URIs this layer must never import.                                                                     |
| `severity`         | severity or `{default, mayImport, forbiddenImports}` | no       | Severity for this layer, or per check kind in this layer.                                              |

### Semantics

- `files` — package-relative glob patterns. The **first** layer whose pattern
  matches a file's path owns that file; a file owned by no layer is ignored.
- `mayImport` — names of layers this layer may import. Importing a layer that is
  not listed is a violation. Importing a file that no layer owns is not checked.
- `forbiddenImports` — URI glob patterns this layer must never import, matched
  against the URI exactly as written (`package:flutter/**`, `dart:io`, ...).
- Both `import` and `export` directives are checked, covering relative URIs,
  self-package URIs, and external packages.
- `mayImport` entries must name a declared layer; an unknown name is a
  configuration error.

### Severity

Every architectural rule can be as strict as the project needs. The most
specific setting wins:

1. per forbidden-import pattern — `{uri: dart:io, severity: error}`
2. per check kind in a layer — `severity: {mayImport: error, forbiddenImports: warning}`
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

### Messages

| Violation        | Message                                                                           |
| ---------------- | --------------------------------------------------------------------------------- |
| layer boundary   | `Layer 'domain' may not import 'data' (import 'package:app/src/data/repo.dart').` |
| forbidden import | `Layer 'domain' forbids import 'dart:io'.`                                        |

Violations are reported on the offending directive. Configuration errors are
reported at the top of every analyzed file.

## The `encapsulation` rule

State is private and changes only through methods. Each entry selects the
classes it governs and declares what they must satisfy:

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

### Section reference

| Key              | Type     | Required | Meaning                                                           |
| ---------------- | -------- | -------- | ----------------------------------------------------------------- |
| `version`        | int      | no       | Must be `1` when present.                                         |
| `severity`       | severity | no       | Config-wide default for violations. Falls back to the document's. |
| `encapsulations` | list     | yes      | A non-empty list of encapsulations.                               |

### Encapsulation reference

| Key            | Type                                           | Required                   | Meaning                                                            |
| -------------- | ---------------------------------------------- | -------------------------- | ------------------------------------------------------------------ |
| `files`        | glob or list of globs                          | one of `files`/`selectors` | Package-relative patterns of the files this encapsulation governs. |
| `selectors`    | list of selector objects                       | one of `files`/`selectors` | Element-based selection; any match selects the class.              |
| `requirements` | map of flags, or a list of requirement entries | no                         | What selected classes must satisfy. Defaults shown below.          |
| `severities`   | map of requirement names to severities         | no                         | Per-requirement severity overrides.                                |
| `severity`     | severity                                       | no                         | Overrides the config-wide severity for this encapsulation.         |

Selectors, any match selects the class:

| Selector         | Example                     | Matches                                                                                       |
| ---------------- | --------------------------- | --------------------------------------------------------------------------------------------- |
| `supertype`      | `supertype: ChangeNotifier` | Classes with the supertype among their direct and indirect supertypes, interfaces, or mixins. |
| `nameEndsWith`   | `nameEndsWith: ViewModel`   | Classes whose name ends with the suffix.                                                      |
| `nameStartsWith` | `nameStartsWith: ViewModel` | Classes whose name starts with the prefix.                                                    |
| `annotation`     | `annotation: viewModel`     | Classes annotated with the annotation called that name.                                       |

Requirements and their defaults:

| Requirement            | Default | Meaning                                             |
| ---------------------- | ------- | --------------------------------------------------- |
| `fieldsPrivate`        | `true`  | Instance fields must be private.                    |
| `privateFieldsFinal`   | `true`  | Private instance fields must be `final`.            |
| `noPublicSetters`      | `true`  | Setters must not be public.                         |
| `requirePublicGetters` | `false` | Every private instance field needs a public getter. |

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
only `severity` leaves the flag as it was. The `severities` map sets only the
severity; when both name the same requirement, the entry wins.

### Semantics

- A class is checked when its path matches any `files` pattern or any selector
  matches. Every encapsulation that selects a class constrains it, so one class
  can be governed by more than one.
- An encapsulation must select something: it needs `files`, `selectors`, or
  both, and at least one requirement must be enabled.
- Only instance members are checked; `static` fields and setters are exempt.
- Severity is chosen by the most specific setting: the requirement's own
  `severity` (or the `severities` map), then per encapsulation (`severity`),
  then config-wide.
- `supertype` matching is element-based — `ChangeNotifier` matches subclasses
  too — so enabling this rule turns off the parsed-results fast path for the
  package.
- Violations carry the class name, for example
  `HomeViewModel: field 'count' must be private`.

### Messages

| Violation              | Message                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `fieldsPrivate`        | `HomeViewModel: field 'count' must be private; expose it through a public getter.`                     |
| `privateFieldsFinal`   | `HomeViewModel: private field '_count' must be final; mutate this state through methods.`              |
| `noPublicSetters`      | `HomeViewModel: setter 'count' must not be public; expose read-only state and mutate through methods.` |
| `requirePublicGetters` | `HomeViewModel: private field '_count' has no public getter 'count'.`                                  |

Violations are reported on the member they name; when the member cannot be
located in an incomplete file, they fall back to the class declaration.

## The `placement` rule

Where a declaration lives decides what it is. Each placement declares
conventions for the classes declared in the files it matches:

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

### Section reference

| Key          | Type     | Required | Meaning                                                           |
| ------------ | -------- | -------- | ----------------------------------------------------------------- |
| `version`    | int      | no       | Must be `1` when present.                                         |
| `severity`   | severity | no       | Config-wide default for violations. Falls back to the document's. |
| `placements` | list     | yes      | A non-empty list of placements.                                   |

### Placement reference

| Key                    | Type                                                  | Required                | Meaning                                                                             |
| ---------------------- | ----------------------------------------------------- | ----------------------- | ----------------------------------------------------------------------------------- |
| `files`                | glob or list of globs                                 | yes                     | Package-relative patterns of the files this placement governs.                      |
| `exempt`               | glob or list of globs                                 | no                      | Patterns exempt from this placement, for example `**/*.g.dart`.                     |
| `classesMustEndWith`   | suffix, list of suffixes, or `{suffix, exclude}` maps | one of the three checks | The class name must end with one of the suffixes.                                   |
| `mustHaveSupertype`    | string or list of strings                             | one of the three checks | The class must have one of the supertypes (direct or indirect, interfaces, mixins). |
| `mustNotHaveSupertype` | string or list of strings                             | one of the three checks | The class must not have any of the supertypes.                                      |
| `severity`             | severity                                              | no                      | Overrides the config-wide severity for this placement.                              |

At least one of `classesMustEndWith`, `mustHaveSupertype`, or
`mustNotHaveSupertype` must be declared.

### Semantics

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
- Only class declarations are checked; mixins, enums, and top-level functions
  are out of scope.
- Supertype matching is element-based, so enabling this rule turns off the
  parsed-results fast path for the package, as `encapsulation` does.
- Each placement can override the config-wide `severity` with its own.

### Messages

| Violation                    | Message                                                                       |
| ---------------------------- | ----------------------------------------------------------------------------- |
| name suffix (one)            | `HomeBadge: name must end with 'ViewModel'.`                                  |
| name suffix (several)        | `HomeBadge: name must end with one of 'ViewModel', 'Screen'.`                 |
| required supertype           | `FakeRepository: must extend or implement 'Repository'.`                      |
| required supertype (several) | `FakeRepository: must extend or implement one of 'Repository', 'DataSource'.` |
| forbidden supertype          | `FakeRepository: must not extend or implement 'Repository'.`                  |

Violations are reported on the class name. See
[quick fixes](#quick-fixes) for the correction offered on required-supertype
violations.

## A complete configuration

The example consumer configures all three rules. It keeps the document under
the `synthex_lint` key of its `pubspec.yaml` and ships
`synthex_lint.yaml.bak`, so the pubspec key is the only source that applies.
Shown here at the top level of a `synthex_lint.yaml`, where it works
identically:

```yaml
# synthex_lint.yaml
version: 1
severity: warning # default for rules that do not set their own

architecture:
  version: 1
  severity: warning
  layers:
    - name: domain
      files: ["lib/domain/**"]
      severity: error
      forbiddenImports:
        - dart:io
        - uri: package:flutter/**
          severity: info
    - name: data
      files: ["lib/data/**"]
      severity: error
      mayImport: ["domain"]
    - name: presentation
      files: ["lib/presentation/**"]
      severity: error
      mayImport: ["domain", "data"]

placement:
  version: 1
  placements:
    - files: ["lib/presentation/pages/*"]
      classesMustEndWith: [Page]
      severity: error
    - files: ["lib/presentation/view_models/*"]
      classesMustEndWith: [ViewModel]
      severity: error
    - files: ["lib/presentation/widgets/*"]
      classesMustEndWith:
        - suffix: Widget
          exclude: private
      severity: error
    - files: ["lib/data/**"]
      classesMustEndWith: Repository
      mustHaveSupertype: Repository
    - files: ["lib/domain/use_cases/*"]
      classesMustEndWith:
        - suffix: UseCase
          exclude: private
      severity: error

encapsulation:
  version: 1
  severity: error
  encapsulations:
    - files: ["lib/presentation/view_models/*"]
      severity: error
      requirements:
        - fieldsPrivate:
            enabled: true
            severity: warning
        - privateFieldsFinal: false
        - noPublicSetters: true
        - requirePublicGetters: false
```

With this document in place, the example's `lib/data/repository.dart` reports
`FakeRepository: must extend or implement 'Repository'.` at the document's
`warning` severity — the `placement` section sets none of its own.

## Diagnostics, suppression, and quick fixes

### Diagnostic codes

Each rule reports under its own name — `architecture`, `encapsulation`,
`placement` — at every severity. Internally a rule has one code per severity,
but all of them share the display name, which is why a single ignore comment
covers the rule however it is configured. Configuration errors are reported
under the same codes, at `error` severity.

### Suppressing

```dart
// ignore: synthex_lint/placement
```

The prefixed form is effective from Dart 3.12+. On Dart 3.10 and 3.11 use the
bare form:

```dart
// ignore: placement
```

### Quick fixes

One correction ships with the rules:

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
be a guess. The correction is additive — it inserts text and leaves the rest of
the file alone.

The fix is registered per diagnostic code, and a rule reports under one code per
severity, so `lib/main.dart` registers the fix for all three `placement` codes.

## Troubleshooting

| Symptom                                                     | Cause and fix                                                                                                                                                                                                         |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A rule is enabled under `diagnostics:` but reports nothing. | The document has no section for that rule, or the section is misspelled. Remember that enabling a diagnostic and configuring it are separate steps, and that a typo in a top-level key is reported as a config error. |
| A rule reports nothing for a file that looks governed.      | Check the `files` patterns: they match package-relative POSIX paths, and the path is relative to the package root, not to `lib/`. A pattern without wildcards is an exact match.                                      |
| Config errors appear on every file.                         | The document or one section is invalid; the message names its source (`synthex_lint.yaml 'placement': …`). Read the reported error — a broken configuration is reported rather than ignored by design.                |
| `Unsupported version: …`                                    | The document-level or section-level `version` is not `1`.                                                                                                                                                             |
| `// ignore: synthex_lint/placement` has no effect.          | On Dart 3.10 and 3.11 the prefixed form is not supported; use `// ignore: placement`.                                                                                                                                 |
| Edits to the config document do not apply.                  | They should — the document is re-read by modification stamp. If they do not, check you edited the file the package actually uses: a dedicated `synthex_lint.yaml` wins over the `pubspec.yaml` key.                   |
| Changes to the plugin's own code do not apply.              | Restart the analysis server; plugins are loaded into a separate isolate.                                                                                                                                              |
| `print()` from plugin code shows nothing.                   | Plugins run in a separate isolate, so `print()` does not reach the console. Log to a file instead.                                                                                                                    |
| The example package's `dart analyze` exits non-zero.        | By design: the example ships deliberate violations. Do not wire it into a "must be clean" CI job without excluding it.                                                                                                |
| The example reports `unused_element` for `_Demo`.           | That warning is the analyzer's own, not the plugin's: `_Demo` demonstrates the private-class exemption and nothing references it.                                                                                     |
| A project is slower after enabling a rule.                  | `encapsulation` and `placement` match supertypes, which needs resolved elements, and turn off the parsed-results fast path for the package. `architecture` is syntax-only.                                            |
| `dart pub publish --dry-run` reports style hints.           | Expected: `lib/main.dart` cannot be renamed (the server loads it by name), and the working tree must be committed to clear the "checked-in files are modified" warning.                                               |

## Codebase architecture

```text
packages/synthex_lint/
├── lib/
│   ├── main.dart                     the plugin entry point — the only public library
│   └── src/
│       ├── common/                   helpers shared by rules
│       │   ├── config_document.dart      YAML/JSON decoding
│       │   ├── config_patterns.dart      list-shaped config parsing helpers
│       │   ├── glob_path_matcher.dart    PathMatcher backed by package:glob, with a compile cache
│       │   ├── package_config_source.dart locates, decodes, caches the document; extracts a section
│       │   ├── package_paths.dart        POSIX paths, import classification, pubspec name
│       │   ├── path_matcher.dart         the domain-side matcher port
│       │   ├── rule_keys.dart            each rule's name, defined once
│       │   ├── rule_provider.dart        the RuleProvider port
│       │   ├── rule_resolution.dart      RuleResolution base and config-error reporting
│       │   └── rule_severity.dart        severity parsing
│       ├── rules/
│       │   ├── rule_registry.dart        warningRules and lintRules
│       │   ├── architecture/
│       │   ├── encapsulation/
│       │   └── placement/
│       └── ...
├── test/
└── benchmark/
```

### Layering

- Pure code lives in a `domain/` folder — no analyzer, no `dart:io`, no plugin
  framework; pure utility packages such as `path` and `glob` are fine.
- `<rule>/infrastructure/` implements the domain ports on top of the analyzer
  file system and third-party packages.
- The rule itself is a thin adapter that translates AST facts into domain calls
  and reports diagnostics.
- `lib/src/common/` holds helpers shared by rules; anything only one rule needs
  stays inside that rule's folder. Unlike `domain/`, a shared helper may read
  through the analyzer's file system — the config loader does — but it must
  never depend on a single rule.
- Rules must be stateless: instances are shared by the analysis server, and the
  pipeline may run a rule several times per file.

`test/architecture/domain_purity_test.dart` enforces the first two points: every
`domain/` folder is pure, and no file in `src/common/` reaches into
`src/rules/`. It fails the build on either.

### How a rule gets its configuration

```text
synthex_lint.yaml / pubspec.yaml key
        │
        ▼
PackageConfigSource          locate + decode + cache, extract the rule's section
        │
        ▼
<Rule>Provider               RuleProvider<Resolution> — reads the section
        │
        ▼
<Rule>Parser (domain)        pure parse + validation → config or errors
        │
        ▼
<Rule>Resolution             config + matcher + source + errors
        │
        ▼
<Rule>Evaluator (domain)     pure evaluation of facts → violations
        │
        ▼
<Rule> adapter               reports each violation at its severity
```

## Development

### Commands

Run from `packages/synthex_lint` unless noted:

| Command                                          | What it does                                   |
| ------------------------------------------------ | ---------------------------------------------- |
| `dart pub get`                                   | Resolve dependencies.                          |
| `dart test`                                      | Run the test suite.                            |
| `dart analyze`                                   | Static analysis; expected to be clean.         |
| `dart format .`                                  | Format the package.                            |
| `dart run benchmark/architecture_evaluator.dart` | Measure the pure architecture evaluation path. |
| `dart doc`                                       | Generate API docs for the public library.      |
| `dart pub publish --dry-run`                     | Validate the package before publishing.        |

From the repository root, the example consumer is a standalone package:

```sh
cd examples/consumer
dart pub get
dart analyze
```

### Tests

| Test                                                       | What it covers                                                                                                                                |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/plugin_registration_test.dart`                       | The entry point: the `AddSupertype` fix is registered for every severity code of the `placement` rule.                                        |
| `test/rules/rule_registry_test.dart`                       | The config key set and the registered rules cannot drift apart.                                                                               |
| `test/architecture/domain_purity_test.dart`                | Layering: `domain/` folders stay pure, `src/common/` stays rule-agnostic.                                                                     |
| `test/common/config_document_test.dart`                    | YAML/JSON decoding, by extension and case-insensitively, and decode failures.                                                                 |
| `test/common/config_patterns_test.dart`                    | The list-shaped config parsing helpers and pattern validation.                                                                                |
| `test/common/package_config_source_test.dart`              | Severity fill-in: a section without its own severity gets the document's; a section that has one is left untouched.                           |
| `test/common/package_paths_test.dart`                      | POSIX path handling, relative-to-root math, import classification, pubspec name parsing.                                                      |
| `test/common/rule_provider_test.dart`                      | The `RuleProvider` port is the rule's whole seam: a bare implementer wires into a rule, and the production providers implement the same port. |
| `test/common/rule_resolution_test.dart`                    | Each rule's resolution conforms to the shared `RuleResolution` base, and the config source, matcher, and errors flow through it.              |
| `test/rules/<rule>/<rule>_test.dart`                       | Each rule end to end, with a fixed resolution injected — no file system.                                                                      |
| `test/rules/<rule>/<rule>_workspace_config_test.dart`      | The production provider and `PackageConfigSource`: the pubspec key, the dedicated files, which wins, and document-level errors.               |
| `test/rules/<rule>/domain/…`                               | The pure parsers and evaluators for each rule: validation (unknown keys, unsupported versions, malformed values) and evaluation.              |
| `test/rules/placement/add_supertype_test.dart`             | The correction producer, driven through the analyzer's own `CorrectionProducerContext`.                                                       |
| `test/rules/placement/domain/required_supertype_test.dart` | The message shapes the correction parses.                                                                                                     |
| `test/support/correction_testing.dart`                     | Shared helper that applies a correction's edits and returns the corrected source.                                                             |

### CI

`.github/workflows/ci.yml` runs on every push to `main` and on pull requests:
`dart pub get`, a formatting check
(`dart format --output=none --set-exit-if-changed .`), `dart analyze`, and
`dart test`, all in `packages/synthex_lint`.

### Adding a rule in 3 steps

1. Copy `lib/src/rules/placement/` — the smallest config-driven rule — and
   rename the folder, the class (`<Code>Rule`), and the `LintCode` name to
   match — rule code == folder name. Keep the rule's own folder structure: pure
   Dart under `<rule>/domain/`, analyzer and third-party adapters under
   `<rule>/infrastructure/`, and the rule itself as a thin adapter next to them.
   Promote a helper to `lib/src/common/` only when a second rule needs it.
2. Register it in `lib/src/rules/rule_registry.dart` — under `warningRules` (on
   by default) or `lintRules` (opt-in per project).
3. Add `test/rules/<name>_test.dart` mirroring the reference test, plus a demo
   file in the repo's `examples/consumer/`. A config-driven rule also needs a
   workspace-config test (see `encapsulation_workspace_config_test.dart`)
   proving the config is read from both sources.

### Conventions

- Rule code == folder name. A rule's name is its identity — the diagnostic
  code, the `diagnostics:` entry, the config section, and what `// ignore:`
  matches — so it is defined once in `lib/src/common/rule_keys.dart` and every
  rule takes it from there.
- A rule's `LintCode` must be a single `static const` field; `// ignore:`
  comments match diagnostics by that code's identity.
- Each config-driven rule keeps one provider under `<rule>/infrastructure/` that
  reads its section of the document through `PackageConfigSource` and parses it
  with its own pure parser in `<rule>/domain/`. The rule accepts that provider
  as `RuleProvider<…>`: the port is the rule's whole seam.
- A resolution extends `RuleResolution` and carries the config source, the
  matcher, and the configuration errors found; the subclass adds the rule's
  typed configuration. `reportConfigErrors` reports the errors for any rule.
- Corrections live under `<rule>/infrastructure/` and are registered in
  `lib/main.dart`: a fix per diagnostic code. A correction must be additive,
  must leave the file compiling, and must produce no edit rather than guess.
- Never rename a diagnostic code without a CHANGELOG note; users' ignore
  comments reference it.
- Split the visitor into its own file only when the rule file grows past ~120
  lines.
- Every public member in `lib/` carries a doc comment; the
  `public_member_api_docs` lint in `analysis_options.yaml` enforces it.

### Dev-loop notes

- `print()` does not reach the console in plugins (they run in a separate
  isolate) — log to a file instead.
- Restart the analysis server after changing plugin code.
- `lib/main.dart` is the entry point the server loads, so it cannot be renamed
  to match the package name; `dart pub publish --dry-run` reports that as a
  style hint, along with a "checked-in files are modified" warning until the
  working tree is committed. Both are expected.

## Publishing to pub.dev

The published package is `packages/synthex_lint`.

### Checklist

1. Bump `version` in `pubspec.yaml` and add a `CHANGELOG.md` entry.
2. `dart analyze` — clean (the package enables `public_member_api_docs`, so a
   public member without a doc comment fails this).
3. `dart test` — all green.
4. `dart doc --dry-run` — no warnings or errors.
5. `dart pub publish --dry-run` — only the two expected hints (see
   [dev-loop notes](#dev-loop-notes)).
6. Publish: the first version manually with `dart pub publish`; later versions
   by pushing a version tag, once automated publishing is configured (below).

### Releasing with GitHub Actions

`.github/workflows/publish.yml` runs when a `vX.Y.Z` tag is pushed: it analyzes
and tests the package, then publishes `packages/synthex_lint` with the official
reusable workflow, `dart-lang/setup-dart/.github/workflows/publish.yml@v1`,
which authenticates with a short-lived OIDC token instead of a stored secret.

One-time setup, after the package's first manual publish:

1. On pub.dev, open the package's **Admin** tab → **Automated publishing** →
   **Enable publishing from GitHub Actions**.
2. Enter the repository (`<owner>/<repository>`) and the tag pattern
   `v{{version}}` — it must match the pattern in `.github/workflows/publish.yml`.

Releasing a version is then:

```sh
# version and CHANGELOG are already committed on main
git tag v0.2.0
git push origin v0.2.0
```

Anyone who can push a matching tag can publish, so consider hardening the setup
on pub.dev by requiring a GitHub Actions environment (`pub.dev`) and adding it
to the publish job's `with:` block, with protection rules on the GitHub side.

### What pub.dev shows

- The package README ([`packages/synthex_lint/README.md`](../packages/synthex_lint/README.md))
  is the landing page; keep it current.
- The **API reference** is generated with dartdoc, which documents the package's
  public libraries. This package has exactly one: `lib/main.dart`, exposing the
  `plugin` variable and `SynthexLintsPlugin`. Everything else lives under
  `lib/src/` and is deliberately not part of the published API — it can change
  without notice.
- The documentation score covers the public library; the
  `public_member_api_docs` lint keeps the whole source documented, public or
  not, so the published API can never be the undocumented part.

## License

BSD-3-Clause — see [LICENSE](../LICENSE).
