# Recast

A macOS menu bar app that rewrites whatever you're typing — in any app — with Claude, using your claude.ai subscription via OAuth.

Press a global shortcut (default **⌘⇧R**) while typing anywhere. Recast grabs your text (the selection if you have one, otherwise the whole field), rewrites it with Claude, applies the first suggestion instantly, and shows a small popup with your original plus all variants. Click a variant to swap, **Esc** to revert. Everything is saved to a local, searchable history.

## Build

Requires macOS 14+ and the Xcode Command Line Tools (`swift` on PATH).

```sh
./build.sh                 # builds release → Recast.app
ditto Recast.app /Applications/Recast.app
open /Applications/Recast.app
```

## First-run setup

1. **Accessibility permission** — macOS prompts on first launch. Grant it in
   System Settings → Privacy & Security → Accessibility. Needed to read and
   replace the text you're editing. The build is signed with a local
   "Recast Dev" certificate so the grant survives rebuilds.
2. **Connect with Claude** — click the wand icon in the menu bar →
   "Connect with Claude…". Your browser opens claude.ai; approve, and the
   tokens are stored in your Keychain.
3. Type anywhere and press **⌘⇧R**.

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
