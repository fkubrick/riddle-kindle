# riddle-kindle

A handwritten diary for jailbroken Kindle readers. Write on the page, watch the ink spread into the paper, and receive a reply emerging in small word blocks. Inspired by [MaximeRivest/riddle](https://github.com/MaximeRivest/riddle) and built on [Ink Away](https://github.com/EmirErtorer/ink-away.koplugin) inside KOReader.

This is the Kindle client and its handwriting renderer. A compatible HTTPS relay and a separate assistant are required for replies. The relay protocol is documented in [PROTOCOL.md](PROTOCOL.md). The original riddle application targets reMarkable hardware.

## Status

Writing, persisted outgoing pages, connected replies, draft preservation, swipe navigation and burning holes have been used on a jailbroken Kindle Paperwhite 3 running firmware 5.12.4. The new ink absorption, block reveal and automatic reply expiry have passed local LuaJIT checks; their appearance and timing on the physical display still need confirmation. Other devices are untested.

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

- Write, then lift your finger or capacitive stylus. After five seconds of inactivity, the journal saves and queues the page.
- Swipe right while reading to return to writing.
- Swipe left from the right edge while writing to view the latest reply. The draft is retained and its send timer pauses during reading.
- Swipe down from the top edge while reading to open KOReader’s menu.
- Tap to reveal the bottom fallback controls, which hide after five seconds. Reading offers Fermer / Écrire. Writing offers Fermer.
- Hold for at least 350 ms to place an intentional ink dot.

Replies replace the previous displayed reply automatically. A reply arriving while you write waits while your draft is preserved. Unsent pages survive closing and reopening. Up to eight queued pages/replies are retained, with the active draft kept when the queue is full.

If the main journal state is empty or missing after an interrupted save, opening the journal can recover a fully validated pending `.part` file. A valid main state always takes precedence. Nonempty damaged files and incomplete pending writes are left untouched for manual recovery.

The user-facing controls are currently French. The plugin receives replies from the configured relay every five seconds when idle. Assistant response latency depends on the external assistant and its notification mechanism.

## Ink effects

After queuing, the submitted ink diffuses across the page for thirty-five seconds. Network requests continue during diffusion. If no reply has arrived when it ends, small, discreet drops loop every twenty seconds until one arrives. There are no prerecorded waiting phrases. Returning to writing cancels the visual effect without cancelling delivery.

Ordinary requested replies emerge in small groups of words, from diffuse ink to sharp letters. Their complete layout stays fixed. A reply remains visible for thirty seconds after it has fully appeared, then clears. Swipe left from the right edge to replay it. A draft retained while reading stays intact and does not send when the reply expires; writing another stroke resumes its inactivity timer. Unsupported glyphs use the text fallback.

Spontaneous replies remain visible until a user gesture or another message replaces them; they do not expire automatically.

**Paper burning is optional and disabled by default.** To enable it, add `"paper_burn": true` to your private `koreader/settings/alfred-ink.json` and reopen the journal. Burning occurs only when a requested reply arrives with the explicit `effect: "burn"` instruction. Submitted pages are never selected randomly for burning, and spontaneous messages do not burn.

The burn opens scattered holes with irregular dark edges that grow and merge until the page is white. The pattern varies each time. The ink lightens and darkens through black-and-white stippling. Animation uses KOReader's fast refresh on the affected regions, including the small areas around waiting drops. Ghosting and display cadence vary by device.

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
