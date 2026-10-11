# Changelog

## [Unreleased]

## [0.3.1] - 2026-10-11

- Load stored conflicts even while disconnected so they remain reviewable after relaunch.
- Require explicit resolution before joining a new pairing group, retaining unreviewed alternatives.
- Carry deletion markers into a new group without carrying old device clocks, preventing silent resurrection during re-pairing.

## [0.3.0] - 2026-10-11

- Add NativeSync for opt-in encrypted Mac/iPhone sync over Bonjour/TCP, with per-device pairing credentials and automatic reconnect.
- Preserve offline edits with causal clocks, safe field/ID-array merging, durable tombstones and explicit whole-record conflict review.
- Add a recoverable sync journal integrated under app/CLI repository locks; reject invalid projections and block unreviewed conflict edits.
- Add NativeUI pairing/status/conflict settings and a compiled fictional repository/loopback example.
- Require fresh PSK proof on reconnection, bound frames/queues/handshakes and discard callbacks from old pairing generations.
- Document foreground/local-network limits, app-specific shared scope and device testing; installed apps still need rebuilding and release.
- Keep the existing agent import contract, minimum platforms and dependency-free root products; NativeUI now also depends on NativeSync.

## [0.2.0] - 2026-10-11

- Reuse library primitives inside Keep Close and City without changing their existing data formats.
- Add configurable legacy JSON date encoding, synchronous file locking, atomic file writes and recovery helpers.
- Add strict decoding for existing import envelopes, stable-ID checkpoint comparisons and native clipboard/file transfer.
- Add a reusable authentication gate and configurable per-device Keychain accessibility.
- Share verified archive creation and appcast generation with consuming app release scripts.

## [0.1.0] - 2026-10-11

- Add independently importable NativeCore, AgentInterchange, NativeSecurity and NativeUI products.
- Add strict configurable agent handover, preview/selection, provenance, conflict handling and durable checkpoints.
- Add fictional CLI and native examples plus a separate macOS Sparkle adapter.
- Add signed archive/feed preparation, package release workflows and distribution guidance.
