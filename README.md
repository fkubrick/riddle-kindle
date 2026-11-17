# riddle-kindle

A handwritten diary for jailbroken Kindle readers. Write on the page, let the ink dissolve, and receive a reply drawn stroke by stroke. Inspired by [MaximeRivest/riddle](https://github.com/MaximeRivest/riddle) and built on [Ink Away](https://github.com/EmirErtorer/ink-away.koplugin) inside KOReader.

This is the Kindle client and its handwriting renderer. A compatible HTTPS relay and a separate assistant are required for replies. The relay protocol is documented in [PROTOCOL.md](PROTOCOL.md). The original riddle application targets reMarkable hardware.

## Status

Writing, persisted outgoing pages, connected replies, draft preservation and swipe navigation have been used on a jailbroken Kindle Paperwhite 3 running firmware 5.12.4. The latest fragment dissolve, smoother stroke replay and menu changes passed local LuaJIT checks and have been installed on that device. Their appearance on the physical display is awaiting user feedback. Other devices are untested.

The ink renderer is experimental. E-ink refresh modes can leave ghosting and the physical display cadence varies. The plugin keeps the reader awake while open, which increases power use.

## Install

1. Install KOReader for your already-jailbroken Kindle and Ink Away 4.5.2. Back up your existing KOReader settings.
2. Exit KOReader completely and connect the Kindle over USB.
3. Copy this repository’s `koreader/plugins/riddle.koplugin` into the Kindle’s `koreader/plugins/` directory.
4. Copy `koreader/plugins/ink-away.koplugin/ink/alfred` into the matching directory of the installed Ink Away plugin. These four bridge modules depend on Ink Away’s drawing engine, JSON, HTTPS and background worker modules.
5. Copy `examples/alfred-ink.example.json` to `koreader/settings/alfred-ink.json`. Set `relay_url` to your relay’s HTTPS origin without a trailing slash and `token` to your own device bearer token. The token must contain 32–256 supported characters. Configure the relay to accept that token.
6. Safely eject USB, start KOReader and open Tools > Journal · Alfred.

Keep this configuration file private. The client is configured with your relay’s hostname. The assistant must have a separate authenticated way to inspect incoming pages and submit responses on your relay.

## Use

- Write, then lift your finger or capacitive stylus. After six seconds of inactivity, the journal saves and queues the page.
- Swipe right while reading to return to writing.
- Swipe left from the right edge while writing to view the latest reply. The draft is retained and its send timer pauses during reading.
- Swipe down from the top edge while reading to open KOReader’s menu.
- Tap to reveal the bottom fallback controls, which hide after five seconds. Reading offers Fermer / Écrire. Writing offers Fermer.
- Hold for at least 350 ms to place an intentional ink dot.

Replies replace the previous displayed reply automatically. A reply arriving while you write waits while your draft is preserved. Unsent pages survive closing and reopening. Up to eight queued pages/replies are retained, with the active draft kept when the queue is full.

The user-facing controls are currently French. The plugin receives replies from the configured relay every five seconds when idle. Assistant response latency depends on the external assistant and its notification mechanism.

## Waiting animation

After a queued page dissolves, the diary can display four prerecorded French phrases. They start after about twelve seconds, write over twenty-eight seconds and linger for eight seconds before the next dissolve. They are local visual effects, never assistant messages or transmitted pages. An actual reply interrupts the sequence. Returning to writing cancels it.

The phrases are “Un instant...”, “La page reste ouverte.”, “L’encre attend la suite.” and “Le silence a aussi son écriture.” The precompiled paths are in `waiting-paths.json`.

## Source layout

`riddle.koplugin` contains journal state, gesture handling, animations and the connector. `ink/alfred` contains the Ink Away bridge. `tools/riddle_paths.py` converts text into trajectories using the included Dancing Script alphabet. Unsupported glyphs can fall back to text rendering in the client.

## Credits and licensing

- Riddle by Maxime Rivest supplied the inspiration and deterministic dissolve hash. Its MIT notice is included with the plugin and renderer.
- Ink Away by Emir Devlet Ertörer provides pen capture and the canvas, under MIT. Its notice is included at the repository root.
- Dancing Script uses SIL OFL 1.1. Its notice accompanies the alphabet-derived trajectories.
- KOReader is a separate dependency under AGPL-3.0. This adaptation is distributed under AGPL-3.0-or-later, with the upstream MIT and OFL notices retained.

## Privacy

The journal sends page coordinates and fetches responses only from the configured relay. Drafts and the outgoing queue are stored in KOReader settings. This source distribution contains generic examples and the code needed to connect your own service. It includes no hosted service, bundled assistant account or API subscription.

## Local checks

With Python and `lupa` installed, run `python tests/run.py --ink-away-root /path/to/ink-away.koplugin` against the Ink Away version used on the device. This checks Lua syntax, configuration validation, the relay protocol, persisted state and response replacement. Physical animation and gesture behavior require a device test.
