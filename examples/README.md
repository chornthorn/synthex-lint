# Examples

Runnable examples of using the packages in this repo.

| Example                  | What it shows                                                               |
| ------------------------ | --------------------------------------------------------------------------- |
| [`consumer/`](consumer/) | Enables the `synthex_lint` analyzer plugin and demonstrates rule reporting. |

Each example is a standalone package (`publish_to: none`). To try one:

```sh
cd consumer
dart pub get
dart analyze
```

Deliberate diagnostics are part of the demo — an example is expected to
report the rule it advertises.
