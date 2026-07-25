# Changelog

All notable changes to PaneCue will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/) once the first
public release is published.

## Unreleased

### Added

- Context-aware built-in workspace scenarios.
- Visual custom scenario editor with multi-window layouts.
- Local Auto Mode suggestions that require user approval.
- Floating call and browser video with playback controls.
- Automatic, Offline Only, and Cloud Only voice processing.
- PaneCue Mini v2 local command model.
- Command Lab for testing and correcting natural-language layouts.
- One-time guided setup for macOS permissions.
- Adaptive macOS application icon styles.

### Security

- OpenAI API keys are stored in macOS Keychain.
- Voice and workspace actions are restricted to an allow-listed command set.
- Permissions are requested only when their related feature is selected.
