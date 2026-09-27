# consumer

Minimal package that enables the
[`synthex_lint`](../../packages/synthex_lint) analyzer plugin.

## Run it

```sh
dart pub get
dart analyze
```

Expected: two diagnostics.

```text
warning • lib/data/repository.dart:9:7 • FakeRepository: must extend or implement 'Repository'. • placement
warning • lib/domain/use_cases/get_user_usecase.dart:3:7 • The declaration '_Demo' isn't referenced. Try removing the declaration of '_Demo'. • unused_element
```

Where they come from — every rule is configured in one document, and this
package keeps it under the `synthex_lint` key of
[`pubspec.yaml`](pubspec.yaml); the dedicated `synthex_lint.yaml` is kept as
`synthex_lint.yaml.bak`, so nothing else applies:

- the `placement` section — where a class lives decides what it is.
  `lib/data/repository.dart` declares a `FakeRepository` that does not implement
  the domain's `Repository` contract, which the `data` placement requires. The
  document's own `severity: warning` is what makes that a warning: the
  `placement` section sets no severity of its own.
- the `placement` section's `use_cases` entry requires public classes in
  `lib/domain/use_cases/*` to end with `UseCase`, and exempts private ones:
  `GetUserUseCase` satisfies it and `_Demo` is left alone, so neither is
  reported.
- the `unused_element` warning is the analyzer's own, not the plugin's: `_Demo`
  demonstrates the exemption, and nothing references it.
- the `architecture` and `encapsulation` sections are configured and report
  nothing: the demo's files are clean, and `requirePublicGetters` is `false`.
  Add `import 'dart:io';` to `lib/domain/entity.dart` to see the architecture
  rule report, or turn the requirement on to see the encapsulation rule report.

`dart analyze` shows the violations; the corrections are offered in an IDE.
`lib/data/repository.dart` is where to see the plugin's one correction, the
`AddSupertype` fix on `FakeRepository`. The encapsulation violations offer no
correction: the rule reports four requirements under one diagnostic code, so a
fix could answer only one of them.

See the [plugin README](../../packages/synthex_lint/README.md) for every
config format.

`dart analyze` exits non-zero here by design — the violations are the point. Do
not wire this package into a "must be clean" CI job without excluding it.

## Adding a rule demo

When a new rule lands in the plugin, add a file here that violates it (and,
if useful, one that suppresses it) so `dart analyze` keeps proving the
plugin works in a real consumer.
