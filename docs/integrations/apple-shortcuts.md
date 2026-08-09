# Apple Shortcuts and Raycast

PaneCue v0.2 exposes only three external routes: show the app, prepare a
visible Preview from text, or prepare a visible Preview from a saved Cue.
Every external request stops at Preview. Only the user-facing **Apply** button
inside PaneCue can move windows.

## Prepare PaneCue Arrangement

Create a shortcut named `Prepare PaneCue Arrangement` with these actions:

1. **Ask for Input**
   - Input type: Text
   - Prompt: `Describe the workspace for PaneCue`
2. **URL Encode** the result of Ask for Input.
3. **Text** with this value:

   ```text
   panecue://preview?text=[URL Encoded Text]
   ```

   Insert `URL Encoded Text` as a Magic Variable; do not type the brackets.
4. **Open URLs**, using the Text action as its input.

On the first run, macOS asks whether this shortcut may open PaneCue. Allowing
that prompt grants only this shortcut permission to open the application. It
does not grant Accessibility access or permission to move windows.

## Open PaneCue Cue

Copy a Cue identifier from PaneCue, then create a shortcut named
`Open PaneCue Cue`:

1. **Ask for Input**
   - Input type: Text
   - Prompt: `Paste a saved Cue UUID`
2. **Text** with this value:

   ```text
   panecue://cue?id=[Provided Input]
   ```

   Insert the Ask for Input result as a Magic Variable.
3. **Open URLs**, using the Text action as its input.

For a one-tap personal shortcut, replace Ask for Input with a Text action that
contains a Cue identifier copied from your own PaneCue library. Do not publish
that personalized shortcut in a shared repository.

## Why the repository has no `.shortcut` download

Apple exports a shortcut for public sharing as an opaque, server-signed
container. Its actions cannot be reviewed in a normal source diff before
installation. PaneCue therefore publishes the short, auditable recipes above
instead of an unreviewable binary. Creating the shortcuts manually also avoids
sending a copy to Apple for export validation.

## Raycast examples

The simplest Raycast Quicklink only brings PaneCue forward:

```text
panecue://show
```

A Raycast Script Command can prepare a Preview from its first argument while
percent-encoding the text locally:

```zsh
#!/bin/zsh

encoded=$(
  /usr/bin/osascript -l JavaScript \
    -e 'function run(argv) { return encodeURIComponent(argv[0]); }' \
    "$1"
)
/usr/bin/open "panecue://preview?text=${encoded}"
```

A second Script Command can open a saved Cue in Preview. Replace the
placeholder locally; never commit a personal Cue identifier:

```zsh
#!/bin/zsh

/usr/bin/open "panecue://cue?id=<cue-uuid>"
```

None of these examples has an Apply route. A web page, Raycast command, Apple
Shortcut, or other external caller can only reveal a visibly marked PaneCue
Preview and wait for a direct decision inside PaneCue.

## Verification record

The two recipes were built and run in Apple Shortcuts on macOS 26 Apple
Silicon. Each opened PaneCue's Quick Cue with the visible labels
`External request · Review before Apply` and `External Preview`. No window was
moved, and the result remained blocked until the in-app Apply control could be
used. The exported public-sharing files were deliberately excluded after
confirming that their signed container is opaque to source review.

Apple documents the relevant actions and export behavior in:

- [Use Ask for Input](https://support.apple.com/guide/shortcuts-mac/apd68b5c9161/mac)
- [Use another app's URL scheme](https://support.apple.com/guide/shortcuts-mac/apd68802640c/mac)
- [Share shortcuts on Mac](https://support.apple.com/guide/shortcuts-mac/apdf01f8c054/mac)
- [Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)
