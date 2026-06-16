# TODO — AirBook for CrossPoint

Tracking persistente. Master plan completo: `~/.claude/plans/purring-snuggling-grove.md`.

## Status legend
- [ ] not started · [~] in progress · [x] done · [-] deferred · [!] stubbed

---

## Phase 0 — Build Fix ✅
- [x] `SyncView.swift` rewrite (`sync.start`, progress derivato da phase, 13 cases `Action`, switch esaustivo)
- [x] `ContentView.swift:172` — `store.deviceLibrary` → `store.deviceStates`
- [x] `xcodebuild` pulito

## Phase 1 — Library Foundations + meta v2 ✅
- [x] `BookMetadata`, `ReadingState` (+ `ProgressMark`, `BookmarkRecord`, `HighlightRecord`, `HighlightColor`, `DirtyFlags`), `ReadingStateStore` (LRU 32), `CollectionsStore`
- [x] `Book.metadata` esteso + decoder backward-compat
- [x] Migrazione v1→v2 con `.v1.bak` snapshot
- [x] App entry: inject ReadingStateStore, CollectionsStore, MetadataLookupService
- [x] Layout `Documents/` (Covers/, BookState/, metadata_cache/)

## Phase 2 — Per-book Status Badge ✅
- [x] `BookLibraryStatus` enum (10 stati) + `BookStore.libraryStatus(for:sync:)`
- [x] `BookStatusBadge` + `CircularMicroProgress` (upload)
- [x] BookCardView: badge + autore
- [x] SyncManager condiviso via environment (badge live durante sync)

## Phase 3 — EPUB Metadata + Online Lookup ✅
- [x] `EpubMetadataExtractor`: `MinimalZipReader` (EOCD + central dir + local headers) + raw deflate via `COMPRESSION_ZLIB` + XMLParser per container/OPF + cover EPUB 2/3
- [x] `MetadataLookupService` Google Books + OpenLibrary parallel, dedup, cache 30g
- [x] `BookDetailView` completo (edit, lookup, free file, delete)
- [x] `MetadataLookupSheet` con cover async
- [x] `BookCoverView` carica cover reale o procedurale fallback
- [x] Wire `importBook` → fire-and-forget extractor + cover save

## Phase 4 — Sort / Filter / Search / Collections ✅
- [x] `LibraryQuery` + `apply` (5 sort, device-state filter, AND su collezioni)
- [x] `LibraryToolbar` (search + sort + chips)
- [x] `CollectionsManagerView` (CRUD)
- [x] BookDetailView chips collezioni con `+` menu
- [x] ContentView `visibleBooks` + `NoMatchView`

## Phase 5 — BLE Protocol V3: progress + bookmarks ✅

### iOS
- [x] `SYNC_START_V3` con fallback automatico a V2 su `ERROR:`
- [x] `ProtocolVersion` enum con `freeHeapKB` da SYNC_READY_V3
- [x] `parseFileV3` esteso con has_progress + bmk_count + hl_count
- [x] Reading-state phase tra LIST_V3 e file ops (per-book queue)
- [x] Pull progress: device-newer → save locale
- [x] Push progress: local-newer → send PUSH_PROGRESS
- [x] Pull bookmarks streaming BMK_V3 + merge by ID
- [x] Push bookmarks: binary blob su Data char + pump resume
- [x] `SyncSummary` esteso (progressMerged, bookmarksMerged, highlightsMerged)
- [x] Per-book error tolerance in reading-state phase
- [x] Trace log ring buffer (per SyncDiagnosticsView)

### Firmware
- [x] `BookmarkEntry.id` (UUIDv4) + lazy upgrade legacy
- [x] `JsonSettingsIO::{save,load}Bookmarks` esteso con id + spine fields
- [x] `util/AirBookUuid` (esp_random V4, normalize, validate)
- [x] `util/AirBookIndex` (`/AirBook/.airbook_index.json` atomic, reconcileWithDirectory)
- [x] `BluetoothFileReceiver`: V3 routing in `onControlWrite`
- [x] `SYNC_START_V3` → `SYNC_READY_V3:<free_kb>` (ESP.getFreeHeap)
- [x] `LIST_V3` con progress existence + bookmark + highlight counts
- [x] `START_V2:<uuid>:<size>:<name>` → upload + persist index + `DONE_V2:<uuid>`
- [x] `DELETE_ENTRY` / `DELETE_FILE` con UUID
- [x] `QUERY_PROGRESS` real impl: read `progress.bin` (6B) + `progress_mtime.bin` (8B)
- [x] `PUSH_PROGRESS` real impl: write entrambi i file binari
- [x] `EpubReaderUtils::saveProgress` esteso per scrivere `progress_mtime.bin`
- [x] `QUERY_BOOKMARKS` streaming BMK_V3 + lazy UUID upgrade
- [x] `PUSH_BOOKMARKS` blob binario su Data char + parser RISC-V-safe (memcpy)
- [x] Heap discipline: cap 30 bookmarks/push, blob buffer pre-reserve

## Phase 6 — Highlights ✅ (storage + sync done; reader integration deferred)

### Firmware
- [x] `HighlightEntry` struct (UUID, xpath_start/end, offsets, color, note, mtime)
- [x] `JsonSettingsIO::{save,load}Highlights` (JSON; binary upgrade = Phase 6c)
- [x] `QUERY_HIGHLIGHTS:<uuid>` → stream HL_V3 records (base64) + HL_END
- [x] `PUSH_HIGHLIGHTS:<uuid>:<count>` → binary blob su Data char + parse + save JSON
- [x] Storage path: `/.crosspoint/highlights/<book>.json`
- [x] `LIST_V3` ora include highlightCount reale
- [x] Cap 50 highlights/push per heap discipline

### iOS
- [x] `SyncManager` reading-state phase: dopo bookmarks → highlights pull/push
- [x] HL_V3 / HL_END / HL_OK handlers
- [x] `encodeHighlightsBlob` binary format matching firmware parser
- [x] `mergeHighlights` union by ID, local-wins overlap
- [x] `BookDetailView` sezione Highlights con lista + remove
- [x] `HighlightAddSheet` manual entry form (xpath, snippet, color, note)
- [x] Error tolerance esteso a highlight push

### Phase 6b ✅ (reader menu + list + jump)
- [x] `EpubReaderMenuActivity` ora include voce "Highlights" tra Bookmarks e Rotate
- [x] `EpubReaderHighlightsActivity.{h,cpp}` — clone del pattern bookmarks: legge stesso JSON che AirBook syncronizza, lista con nota + xpath snippet, jump-to-page via `ProgressMapper::toCrossPoint`, hold-Confirm per delete
- [x] i18n: `STR_HIGHLIGHTS`, `STR_NO_HIGHLIGHTS`, `STR_CONFIRM_DELETE_HIGHLIGHT` (English; altre lingue fallback)
- [x] Wiring in `EpubReaderActivity::onReaderMenuConfirm`

### Deferred (Phase 6c — task #13)
- [ ] Render overlay sui run di testo durante la lettura (4 hatch pattern per colore su display 1-bit) — richiede hook in `lib/Epub/Section.cpp` + `lib/GfxRenderer` per intersezione xpath_start..xpath_end

## Phase 7 — Free Space UI + Cleanup ✅
- [x] BookDetailView free-file + undo
- [x] ContentView context menu free-space
- [x] Delete `SendView.swift`, `BluetoothManager.swift`
- [x] Rename `Item.swift` → `BookStore.swift`

## Phase 8 — Polish + Diagnostics + Tests ⚠️ (diagnostics done; localization/tests deferred)
- [x] `Views/SyncDiagnosticsView.swift` — hidden long-press masthead: trace log + protocol + summary
- [x] BLE trace ring buffer in SyncManager (80 entries)
- [ ] Localize iOS strings via `Localizable.strings` (low priority)
- [ ] Localize firmware strings via `tr()` (low priority — many are debug)
- [ ] Unit tests: BookStoreMigration, EpubMetadataExtractor, MetadataLookupService, SyncMergeLogic

---

## Decisioni architetturali (non perderle)

1. **Protocollo V3 strettamente additivo + fallback V2** in iOS. Firmware: V1 + V3 coesistono in `onControlWrite` (V3 check first).
2. **Sidecar files** per reading state (iOS `Documents/BookState/<uuid>.json`, firmware `/.crosspoint/{bookmarks,highlights}/<book>.json`, `progress.bin` + `progress_mtime.bin` next to reader cache).
3. **AirBook index firmware** `/AirBook/.airbook_index.json` mappa iOS UUID ↔ filename, scritto atomic (`.tmp` + rename). Legacy files (V1 upload) ottengono UUID al primo LIST_V3 via `reconcileWithDirectory`.
4. **Highlights storage = JSON** in Phase 6 per semplicità. Binary format (XHLT magic + records) è Phase 6c follow-up.
5. **Highlights creati primariamente da iOS** in v1; device fa pull (futuro: render + view+jump in HighlightsListActivity).
6. **Collezioni iOS-only**, non syncate al device (firmware non ha UI di filtro).
7. **Atomic write ovunque**. `.v1.bak` iOS pre-migration. `.tmp` + rename firmware.
8. **Merge semantics**: pull device → merge in-memory per ID (newest-updatedAt wins, local wins su overlap quando manca mtime) → push lista autorevole.
9. **Heap discipline firmware**: cap 30 bookmarks + 50 highlights per push, blob buffer pre-reserved, JSON write atomic, no SD I/O held across mutex except small files.
10. **MTU-safe text protocol**: xpath/summary/note base64-encoded + cap 120 chars input per record.
11. **RISC-V alignment**: tutti i load multi-byte su buffer raw via `memcpy`.
12. **Conflict resolution progress**: device scrive `progress_mtime.bin` quando il reader salva. NTP non disponibile → mtime = 0 → iOS sempre più recente (safe default).

---

## Stato finale build

- iOS: ✅ `xcodebuild` pulito (target iOS 26.4)
- Firmware ESP32-C3: ✅ `pio run` SUCCESS — RAM 33% used, Flash 83% used

## Follow-up tracked

- **Task #12 — Phase 6b**: Reader integration firmware (HighlightCache + renderer hook + HighlightsListActivity)

## Hardware testing checklist (per next on-device session)

- [ ] Flash nuovo firmware su CrossPoint device (`pio run -t upload`)
- [ ] Open AirBook iOS app → tap Sync → V3 handshake → SYNC_READY_V3:<KB>
- [ ] Upload nuovo libro EPUB → conferma cover + metadata estratti localmente
- [ ] Conferma DONE_V2:<uuid> arriva, file in `/AirBook/<filename>`
- [ ] Create bookmark on device → sync → confirm appears in iOS BookDetailView
- [ ] Create bookmark in iOS (manual or future API) → sync → confirm appears on device
- [ ] Add highlight via HighlightAddSheet → sync → confirm JSON file at `/.crosspoint/highlights/<book>.json` on device
- [ ] Read 10 pages on device → sync → confirm % updates in iOS detail view
- [ ] Free space su libro da iOS → sync → confirm file deleted on SD, entry kept
- [ ] Delete book from iOS library → sync → confirm DELETE_ENTRY removes both file and index entry
- [ ] Long-press "AirBook" title → diagnostics shows trace log + V3 + free KB
