# SQLite with FTS5 trigram search, ids as recency

Date: 2026-10-11

Status: accepted

## Context

Slow, unreliable search was the main reason to build myClips. A clipboard history is searched by fragments — part of a URL, a word from the middle of a snippet, a name with or without accents — and the result list is ordered by recency, newest first. The search runs on every keystroke, so it must stay well under one frame even for a large history.

Core Data or SwiftData would be the default on Apple platforms. Neither offers substring search with an index: `CONTAINS` predicates scan every row, and a separate Spotlight index adds a second store to keep in sync.

## Decision

Store everything in one SQLite file, using the system `SQLite3` library directly (no dependency):

- An FTS5 table with the `trigram` tokenizer and `remove_diacritics 1` indexes the searchable text. Any substring of three or more characters matches, ignoring case and accents. Tokens shorter than three characters fall back to `LIKE`.
- **Item ids are recency.** Using a clip again (re-copying or pasting it) moves it to a new highest id. Foreign keys follow with `ON UPDATE CASCADE`, and a trigger moves the FTS row. A history search then walks the FTS index by `rowid DESC` and stops at the result limit, instead of collecting every match and sorting it by a timestamp.
- Pinned clips are a second, small query placed before the rest.

## Consequences

- At 100,000 clips, searches of three or more characters take under 1 ms (they took ~65 ms when sorting by `used_at`). `MyClipsBench` measures it.
- A 1–2 character query with no matches still scans everything (~23 ms at 100k, ~2 ms at the default 10k history limit).
- Ids are not stable: anything holding a clip id must expect it to change after the clip is used. The UI reloads after every change; `markUsed` returns the new id.
- Schema changes are hand-written migrations in `Store.migrate`, each covered by a test that upgrades an older database.
