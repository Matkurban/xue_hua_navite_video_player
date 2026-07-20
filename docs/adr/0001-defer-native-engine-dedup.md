# ADR 0001 — Defer native engine adapter deduplication

## Status

Accepted

## Context

iOS and macOS each ship a full Swift plugin (~660–680 LOC) with substantial divergence (~480 diff lines). Linux and Windows each ship a full `mpv_player` implementation. Architecture review suggested sharing one AVPlayer / one MpvPlayer module behind thin OS registration adapters.

## Decision

Do **not** merge native engine sources in this pass. Keep per-platform copies. Reopen when decode / rotation / cover bugs repeatedly require multi-platform patches.

## Consequences

- Locality for engine bugs remains split across OS trees.
- Dart-side seams (`PlayerBackend`, `PlaybackSession`, `MediaProbe`) stay the primary deepening surface.
- Future explorers should not re-suggest engine dedup unless native churn justifies the cost.
