# Contributing to PaneCue

PaneCue is an early macOS project. Focused bug fixes, tests, documentation,
accessibility improvements, and carefully scoped scenario support are welcome.

## Development setup

Requirements:

- macOS 14 or newer
- Swift 6

Build and test:

```sh
swift test
./scripts/package_app.sh
open build/PaneCue.app
```

The packaged application is ad-hoc signed for local development. macOS
permissions belong to that application identity, so replacing the bundle
identifier or signature can require granting permissions again.

## Before submitting a change

1. Keep the change focused and describe the user-facing behavior.
2. Add or update deterministic tests for non-UI logic.
3. Run `swift test`.
4. Confirm that no API keys, Keychain exports, personal data, model
   checkpoints, virtual environments, or packaged builds are included.
5. Explain any new macOS permission, network request, or background behavior.

## Privacy and safety expectations

- Do not move windows without a direct user action or an approved Auto Mode
  suggestion.
- Do not read or transmit window contents unless the feature clearly requires
  it and the interface explains it first.
- Request macOS permissions only when the related feature is used.
- Keep voice actions allow-listed before execution.
- Store credentials in macOS Keychain, never in source files or UserDefaults.

## Training artifacts

The small PaneCue Mini model and its reproducible training data may be tracked.
Large model weights, adapters, checkpoints, GGUF files, Safetensors files,
tool checkouts, and Python environments are intentionally ignored.

## License

Contributions are accepted under the
[Mozilla Public License 2.0](LICENSE).
