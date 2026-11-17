# Relay protocol

Serve the endpoints over HTTPS on the configured origin, using a certificate trusted by KOReader. Authenticate every request with `Authorization: Bearer <device-token>`. Keep assistant write credentials distinct from device credentials. Store a page durably before acknowledging it and use its UUID as an idempotency key for retries.

## POST /native/ink

Accept JSON with `version: 1`, a UUID v4 `id`, `width: 1072`, `height: 1448`, and `strokes`, an array of strokes. Each stroke is an array of integer `[x,y]` pairs in that coordinate space. Limits are 256 strokes, 20,000 points and 262,144 request bytes. Return HTTP 200 or 201 with `{ "id": "the-same-page-uuid", "saved": true }` after durable storage. Validate limits and coordinates on the server.

## GET /native/reply-paths?id=<page-uuid>

Return HTTP 200 and `{ "id": "the-same-page-uuid", "status": "pending" }` until a response exists. When ready, include `status: "ready"`, the same page `id`, a new UUID v4 `message_id`, UTF-8 `text` (at most 640 bytes), and an integer Unix `timestamp`. Optional `paths` are arrays of `[x,y]` trajectories in the 1072×1448 coordinate space. See the validators in `riddlelocal/online_state.lua` for path bounds. The client scales the trajectories to fit the actual screen.

Omitting `paths` uses the text fallback. The entire response must fit 262,144 bytes. Timestamps prevent older responses arriving later from replacing the newest one.

With `paths`, optional `block_ends` is an array of strictly increasing one-based path indexes. Each index ends a word block. The last must equal the number of paths, with at most 160 blocks. `tools/riddle_paths.py` exposes `reply_layout(text)`, returning `paths` and `block_ends` in groups of about two words. The older `reply_paths(text)` interface remains available. Older clients can use these boundaries for a staggered reveal. The current Kindle client reveals all paths together.

For an optional scene, use `[[scene]]` at the start of `text`, followed by two or more nonempty fragments separated by `||`. The relay passes the text through its usual reply endpoint. The Kindle renders the fragments locally. Each fragment before the last is held for three seconds and fades for three seconds. The final fragment follows the usual reading and expiry rules.

Optional `effect` is either `"dissolve"` (ordinary ink) or `"burn"` (burn before revealing). The client honors burn only when its private `paper_burn` option is enabled. Persist these fields alongside the reply so retries and replays retain their presentation. The text-only fallback does not support these vector effects.

Without `id`, the same endpoint represents the spontaneous-message mailbox. A ready spontaneous message has `id` equal to `message_id` and no `reply_to`. A page-specific message in the mailbox with `reply_to` is ignored there and fetched through its page ID. An empty mailbox returns `{ "status": "pending" }`.

Spontaneous replies without an explicit effect default to `"burn"` in the client. This protocol currently carries text and vector handwriting only, not attached images.

The bridge also defines GET `/native/reply`, a text-only variant retained for compatibility. The journal uses `/native/reply-paths`.

## Assistant integration

Present pending page images to your assistant in a protected interface and persist its reply against the page UUID. Process pages oldest first. Triggering the assistant, rendering uploaded strokes as images, and protecting the assistant-facing website are responsibilities of the relay implementation. The repository’s renderer can generate the optional trajectories from reply text.
