# synthex-lint

Dart and Flutter tooling.

## Layout

| Path                                             | What it is                                                                |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| [`packages/synthex_lint`](packages/synthex_lint) | Analyzer plugin: schema-driven architecture rules and other lints.        |
| [`examples/consumer`](examples/consumer)         | Example package that enables the plugin and demonstrates its diagnostics. |

## Quickstart

Try the plugin end to end:

```sh
cd examples/consumer
dart pub get
dart analyze   # reports the deliberate violations in examples/consumer
```

Work on the plugin:

```sh
cd packages/synthex_lint
dart pub get
dart test
```

## Requirements

- Dart 3.10+ / Flutter 3.38+ (analyzer plugin support).

## License

BSD-3-Clause — see [LICENSE](LICENSE).
