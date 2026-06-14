# Recast

A macOS menu bar app that rewrites whatever you're typing — in any app — with Claude, using your claude.ai subscription via OAuth.

Press a global shortcut (default **⌘⇧R**) while typing anywhere. Recast grabs your text (the selection if you have one, otherwise the whole field), rewrites it with Claude, applies the first suggestion instantly, and shows a small popup with your original plus all variants. Click a variant to swap, **Esc** to revert. Everything is saved to a local, searchable history.

## Install & set up

**Requirements:** a Mac running macOS 14 (Sonoma) or later — Apple Silicon or
Intel — and an active [claude.ai](https://claude.ai) subscription.

### 1. Download

Go to the [**Releases**](https://github.com/sagarshah-16/Recast/releases/latest)
page and download **`Recast.zip`**. Double-click it to unzip, then drag
**Recast.app** into your **Applications** folder.

### 2. Open it the first time

Recast is open source but isn't notarized by Apple (that needs a paid Apple
Developer account), so macOS blocks it on the first launch with a *"cannot be
opened because the developer cannot be verified"* message. This is expected —
you only have to get past it once:

- **Right-click** (or Control-click) **Recast.app** → **Open** → click **Open**
  in the dialog.

If macOS still won't open it, run this once in **Terminal**, then try again:

```sh
xattr -dr com.apple.quarantine /Applications/Recast.app
```

After this first time, Recast opens normally like any other app.

### 3. Grant Accessibility permission

On launch, Recast adds a **wand icon** to your menu bar (it has no Dock icon or
window) and asks for **Accessibility** access. Click **Open System Settings**,
then turn **Recast** on under **Privacy & Security → Accessibility**. This lets
Recast read and replace the text you're editing — it's required for the app to
work.

### 4. Connect your Claude account

Click the **wand icon** in the menu bar → **Connect with Claude…**. Your browser
opens to claude.ai — sign in and approve. Recast stores the login token securely
in your macOS Keychain; nothing is shared anywhere else.

### 5. Use it

Type anywhere — Mail, Slack, Notes, a browser — and press **⌘⇧R**. Recast
rewrites your text instantly and shows a popup with the alternatives. Click a
variant to swap it in, or press **Esc** to revert to your original.

## Build from source

Prefer to build it yourself? You need macOS 14+ and the Xcode Command Line Tools
(`xcode-select --install` if `swift` isn't already on your PATH).

```sh
./build.sh                 # builds release for your Mac → Recast.app
ditto Recast.app /Applications/Recast.app
open /Applications/Recast.app
```

`build.sh` signs the app with a local "Recast Dev" certificate when present so
the Accessibility grant survives rebuilds; otherwise it ad-hoc signs. To produce
the universal, zipped build that ships on Releases:

```sh
./package.sh               # universal Recast.app + Recast.zip
```

## Settings

- **General** — change the shortcut, pick the model (Haiku 4.5 default for
  speed), manage the Claude connection and permissions.
- **Rewrite styles** — fully customizable categories. Each row is a name +
  prompt; the first style in the list is the one auto-applied. Add, edit,
  reorder, or delete styles.

## How it works

- **Capture**: tries the macOS Accessibility API first (flicker-free,
  in-place replacement). Falls back to a clipboard-preserving ⌘A/⌘C/⌘V
  sequence for apps with poor AX support (many Electron apps). Refuses to
  run in secure (password) fields.
- **Rewrite**: one Messages API request per style, fired in parallel with
  your OAuth bearer token — the first style is applied the moment it lands
  and the popup fills in the rest. Styles with their own shortcut
  (Settings → Rewrite styles) are applied instantly with no popup.
- **History**: stored locally at
  `~/Library/Application Support/Recast/history.json` (last 500
  rewrites). Browse/search via menu → History, clear anytime.

## Notes & limitations

- The Claude OAuth flow is the same one Claude Code uses. It works today but
  is not an officially supported third-party surface — if Anthropic changes
  it, switching this app to an API key is a small change in
  `Sources/Recast/Rewrite/RewriteService.swift`.
- In clipboard-fallback apps, swapping variants uses undo (⌘Z) + paste, so
  the target app must support undo.
- Tokens live in the macOS Keychain; nothing is sent anywhere except
  `claude.ai` / `console.anthropic.com` / `api.anthropic.com`.

## License

[MIT](LICENSE) — not affiliated with or endorsed by Anthropic.
