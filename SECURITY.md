# Security Policy

## Supported version

PaneCue is currently an early prototype. Security fixes are applied to the
latest code on the `main` branch; there is not yet a supported stable release.

## Reporting a vulnerability

Please do not publish credentials, private data, exploit code, or detailed
reproduction steps in a public issue.

Once private vulnerability reporting is enabled for the GitHub repository,
use **Security → Report a vulnerability**. Until then, open a minimal issue
that says a private security report is needed, without including sensitive
details.

Useful reports include:

- the affected PaneCue version or commit;
- the relevant macOS version;
- which permission or feature is involved;
- the expected and observed behavior;
- whether credentials, audio, window contents, or other private data may be
  exposed.

## Security boundaries

PaneCue uses macOS Accessibility, Screen Recording, Microphone, Speech
Recognition, Automation, and Keychain APIs. A change that expands any of
these permissions or adds a new data destination should be treated as a
security-sensitive change.
