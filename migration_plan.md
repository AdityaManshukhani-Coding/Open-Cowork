# SQLite Migration Plan — OpenCowork

> Ship-blocker M4 from `implementation.md` ("No SQLite storage").
> Replaces the 12-key `UserDefaults` blob storage in `AppStore.swift` with a local SQLite database via [GRDB.swift](https://github.com/groue/GRDB.swift).
> No hosted backend. No recurring cost. Files on the user's disk.

---

## Goals

- Replace `UserDefaults` as the system-of-record for `sessions`, `scheduledTasks`, `skills`, `teams`, `projects`, and `LLMConfig`.
- Get queryability for cost aggregation, history filters, scheduled-task run logs.
- Get atomic per-row writes, schema versioning, and crash-safe migrations.
- Keep zero visual / API change to existing SwiftUI views.
- Keep "all data local, only AI API calls leave the device" privacy promise intact.

## Non-Goals

- Hosted / cloud database (out of scope; SQLite is local).
- Migrating the user from macOS 12 baseline to a higher deployment target.
- Replacing the existing `FileRollbackManager` (file backups stay on disk; SQLite stores metadata).
- A new test framework setup beyond `XCTest` (Tuist supports it natively).

---

## Architectural Decisions

Each baked in from analysis of the actual codebase (`AppStore.swift`, `SchedulerStore.swift`, `TaskSession.swift`, `Project.swift`).

### 1. Concurrency: GRDB `DatabaseQueue` + `await write` from `@MainActor`

**Decision:** `Database` is a final class wrapping a `DatabaseQueue` (not a Swift `actor`). `AppStore` calls `await Database.shared.upsertSession(...)`. GRDB internally dispatches `write` to its serial background queue; UI is never blocked.

**Why not a Swift actor?** Actors introduce reentrancy on every suspension point — a hostile fit for `$sessions.sort(…)` mid-flight. GRDB's `DatabaseQueue` is already thread-safe and battle-tested; we wrap that, not reinvent it.

### 2. Migration safety: SQLite `PRAGMA user_version`, no UserDefaults flag

**Decision:** Drive the one-shot `UserDefaults` → SQLite import from SQLite's own `PRAGMA user_version`. If `user_version == 0` on first launch:

1. Open `BEGIN TRANSACTION`.
2. Read all 12 `UserDefaults` keys.
3. INSERT every row into its target table.
4. `PRAGMA user_version = 1`.
5. `COMMIT`.
6. **Only after the commit**, remove the UserDefaults keys.

If the app crashes anywhere inside steps 1–5, SQLite rolls back. Next launch sees `user_version == 0` and retries safely. No double-import possible because step 6 only runs after step 5 succeeds.

### 3. Schema: Hybrid (shallow normalization + JSON BLOB)

**Decision:** Normalize root columns for queryability; BLOB-deep nested arrays.

| Model | Normalized columns | BLOB column(s) |
|-------|-------------------|----------------|
| `TaskSession` | `id`, `title`, `status`, `createdAt`, `costEstimate`, `isPinned`, `inputTokens`, `outputTokens` | `steps` (`[TaskStep]` JSON) |
| `TaskStep` | `id`, `sessionId` (FK), `seq`, `timestamp`, `status`, `cost` | `payload` (rest of fields as JSON) |
| `ScheduledTask` | `id`, `name`, `cron`, `prompt`, `enabled`, `lastRunAt`, `nextRunAt` | `runHistory` (JSON) |
| `Skill` | `name`, `isEnabled` | `payload` (JSON) |
| `Team` / `Teammate` | `id`, `name` (Team) | `teammates` (JSON) inside Team row |
| `LLMConfig` | `id = 1` (singleton row) | `payload` (JSON) |
| `Project` | `url` (PK), `addedAt` | — |
| `Settings` | `key`, `value` (BLOB) | — (for scalar settings: budget, allowlist toggle, etc.) |

**Why:** This makes "spent by provider this week" a 1-line SQL query (we have `status`, `costEstimate`, `createdAt` as columns) while keeping `[TaskStep]` writes trivially cheap — which is critical for the per-step fire-hazard (decision #5).

### 4. Read pattern: GRDB `ValueObservation` → existing `@Published` arrays

**Decision:** Use GRDB `ValueObservation` to stream the relevant tables directly into `AppStore`'s existing `@Published` arrays. **Zero view changes required.** Background agent completions that UPDATE SQLite auto-propagate to the History view via the @MainActor observer.

**Why:** Today `AppStore.sessions` is bound by `HistoryView`, `ChatView`, `OnboardingView`, `MainPanelView`. Migrating them to `@Query` or per-view loaders is a huge blast radius. `ValueObservation` is the preservation move.

### 5. High-frequency writes: normalize `TaskStep` into its own table — NO debounce

**Decision:** Per-step writes become `INSERT INTO task_steps (...) VALUES (...)` against the normalized `task_steps` table, not a re-encode of the full session blob. No `CoalescingWriter`, no debounce layer.

**Why:** SQLite handles tens of thousands of row-level INSERTs per second. The real cost today is re-encoding the whole session JSON to add one step. Pulling `TaskStep` out eliminates that cost without introducing timer complexity in `AppStore`.

---

## Schema v1 (full DDL)

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;            -- concurrent reads while a writer is active

CREATE TABLE schema_meta (
  user_version INTEGER NOT NULL
);

CREATE TABLE settings (                -- scalar settings: budgetLimit, allowedApps, etc.
  key         TEXT PRIMARY KEY,
  value       BLOB NOT NULL            -- JSON-encoded value
);

CREATE TABLE llm_config (
  id          INTEGER PRIMARY KEY CHECK (id = 1),  -- singleton
  payload     BLOB NOT NULL
);

CREATE TABLE projects (
  url         TEXT PRIMARY KEY,        -- file:// URL string
  added_at    REAL NOT NULL,
  is_active   INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX idx_projects_active ON projects(is_active) WHERE is_active = 1;

CREATE TABLE skills (
  name        TEXT PRIMARY KEY,
  is_enabled  INTEGER NOT NULL DEFAULT 0,
  payload     BLOB NOT NULL
);

CREATE TABLE teams (
  id          TEXT PRIMARY KEY,        -- UUID string
  name        TEXT NOT NULL,
  payload     BLOB NOT NULL            -- JSON excluding `teammates` top-level + edition metadata
);

CREATE TABLE scheduled_tasks (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  cron        TEXT NOT NULL,
  prompt      TEXT NOT NULL,
  enabled     INTEGER NOT NULL DEFAULT 1,
  last_run_at REAL,
  next_run_at REAL,
  payload     BLOB NOT NULL            -- JSON of any extra fields not normalized
);

CREATE TABLE sessions (
  id             TEXT PRIMARY KEY,                 -- UUID string
  title          TEXT NOT NULL,
  status         TEXT NOT NULL,                    -- mirror TaskStatus.raw-ish
  created_at     REAL NOT NULL,
  cost_estimate  REAL NOT NULL DEFAULT 0,
  is_pinned      INTEGER NOT NULL DEFAULT 0,
  input_tokens   INTEGER NOT NULL DEFAULT 0,
  output_tokens  INTEGER NOT NULL DEFAULT 0,
  steps_blob     BLOB NOT NULL                     -- JSON [TaskStep]
);
CREATE INDEX idx_sessions_created_at ON sessions(created_at DESC);
CREATE INDEX idx_sessions_status     ON sessions(status);
CREATE INDEX idx_sessions_pinned    ON sessions(is_pinned DESC, created_at DESC);

CREATE TABLE task_steps (
  id          TEXT PRIMARY KEY,                     -- UUID string
  session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  seq         INTEGER NOT NULL,                     -- position within session
  timestamp   REAL NOT NULL,
  status      TEXT NOT NULL,
  cost        REAL NOT NULL DEFAULT 0,
  payload     BLOB NOT NULL                         -- JSON of remaining TaskStep fields
);
CREATE INDEX idx_steps_session_seq ON task_steps(session_id, seq);
```

All `BLOB` columns are encoded via the standard `JSONEncoder`/`JSONDecoder` that the existing models already use. GRDB's `Codable` record protocol handles this transparently.

---

## File Plan

### New files

| Path | Purpose |
|------|---------|
| `Sources/Services/Database.swift` | `Database` final class — wraps `DatabaseQueue`, exposes typed CRUD. |
| `Sources/Services/DatabaseSchema.swift` | `DatabaseMigrator` with v1 migration. |
| `Sources/Services/DatabaseRecords.swift` | `Codable` conformance bridging GRDB's `FetchableRecord` / `PersistableRecord` for each model. |
| `Sources/Services/MigrationImporter.swift` | One-shot UserDefaults → SQLite importer. |
| `Tests/OpenCoworkTests/DatabaseRoundTripTests.swift` | Round-trip + concurrency + schema tests. |
| `Tests/OpenCoworkTests/UserDefaultsImportTests.swift` | Import tests against fixture plists. |

### Edited files

| Path | Change |
|------|--------|
| `Project.swift` | Add `packages: [.package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")]`; add `OpenCoworkTests` target linked to GRDB. |
| `Sources/Stores/AppStore.swift` | Replace every `defaults.set/get` with `Database.shared.{load,upsert,delete}(...)`. Init kicks off `ValueObservation` streams. |
| `Sources/Stores/SchedulerStore.swift` | No code change — already goes through `appStore.updateScheduledTask(...)`. Verified during testing. |
| `Sources/Models/*.swift` | No changes expected — already `Codable`. (Minor: may add `databaseTableName:` convenience if GRDB adoption warrants.) |

---

## Phased Implementation Steps

### Phase 0 — Pre-flight (15 min)

- Verify `xcodebuild` builds the current `OpenCowork` target cleanly.
- Record the baseline size of `~/Library/Preferences/com.opencode.opencowork.plist` for regression comparison later.
- **Acceptance:** Clean build. Baseline plist size logged.

### Phase 1 — Add GRDB dependency (30 min)

- Edit `Project.swift`:
  ```swift
  packages: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
  ],
  targets: [
    .target(
      name: "OpenCowork",
      // ... existing config ...
      dependencies: [
        .package(product: "GRDB")
      ]
    ),
    .target(
      name: "OpenCoworkTests",
      sources: ["Tests/OpenCoworkTests/**"],
      dependencies: [
        .target(name: "OpenCowork"),
        .package(product: "GRDB")
      ]
    )
  ]
  ```
- Run `tuist generate` (or hand-build if not using Tuist CLI here).
- Verify `import GRDB` resolves in `Sources/Services/Database.swift` (write a one-line placeholder).
- **Acceptance:** Build succeeds; GRDB is linked in both targets.

### Phase 2 — Database core + schema (1h)

- Create `Sources/Services/Database.swift` with:
  - `let shared: Database` singleton.
  - `dbQueue: DatabaseQueue` rooted at `~/Library/Application Support/OpenCowork/store.sqlite`.
  - `init()` runs `migrator.migrate(dbQueue)` then triggers the one-shot import (Phase 6) on first launch.
- Create `Sources/Services/DatabaseSchema.swift` with the `DatabaseMigrator` containing the v1 DDL above.
- Create `Sources/Services/DatabaseRecords.swift` with one `*Record` struct per model (LLMConfigRecord, SessionRecord, StepRecord, ScheduledTaskRecord, SkillRecord, TeamRecord, ProjectRecord).
- **Acceptance:** `xcodebuild` builds without errors. Manual smoke: open `store.sqlite` in `sqlite3`, `.tables` lists the expected tables.

### Phase 3 — Round-trip tests (1h)

Create `Tests/OpenCoworkTests/DatabaseRoundTripTests.swift` with:

| Test | Verifies |
|------|----------|
| `testSessionRoundTrip` | Encode a `TaskSession` with 25 steps → insert → fetch → decode → assert equality. |
| `testStepRoundTrip` | Per-step insert survives; ordering by `seq` is correct. |
| `testScheduledTaskRoundTrip` | Cron + runHistory blob survive. |
| `testCascadeDelete` | Deleting a session removes its steps (`ON DELETE CASCADE`). |
| `testConcurrentWrites` | 100 concurrent step INSERTs from 4 simulated "agent" tasks; final counts correct. |
| `testSchemaVersionBump` | `user_version = 1` after migrate. |
| `testSettingsRoundTrip` | `safetyMode`, `budgetLimit` etc. as JSON blobs. |

Run with `xcodebuild test -scheme OpenCowork -destination 'platform=macOS'`. **Acceptance:** 100% pass.

### Phase 4 — CRUD facade (1h)

- Add to `Database`:
  ```swift
  func loadSessions() throws -> [TaskSession]
  func upsertSession(_ s: TaskSession) throws       // includes step insertion
  func deleteSession(id: UUID) throws
  func upsertSkill(_ s: Skill) throws
  func loadSkills() throws -> [Skill]
  // ... one per current AppStore CRUD method
  ```
- Add `ValueObservation` wrappers that publish into `@Published` arrays on `@MainActor`:
  ```swift
  func observeSessions() -> AnyPublisher<[TaskSession], Error>
  ```
- **Acceptance:** Each method has a unit test in `DatabaseTests`.

### Phase 5 — AppStore rewire (1h)

- Inject `Database.shared` into `AppStore.init`.
- Replace `loadSettings()` body with `await Database.shared.loadAll()`.
- Replace every `defaults.set(…)` in CRUD methods with `await Database.shared.upsertX(…)`.
- Hook `ValueObservation` streams:
  ```swift
  Database.shared.observeSessions()
    .receive(on: DispatchQueue.main)
    .sink { self.sessions = $0 }
    .store(in: &cancellables)
  ```
- **Acceptance:** `xcodebuild` builds. Manually: launch app, exit, relaunch — state persists identically to before.

### Phase 6 — One-shot UserDefaults import (30 min)

- Implement `MigrationImporter.runIfNeeded()` invoked from `Database.init`.
- Logic, gated by `user_version == 0`:
  ```swift
  try dbQueue.write { db in
    // copy every Defaults key into the matching table
    try copyLLMConfig(db)
    try copyScalarSettings(db)
    try copySessions(db)
    try copyScheduledTasks(db)
    try copySkills(db)
    try copyTeams(db)
    try copyProjects(db)
    try db.execute(sql: "PRAGMA user_version = 1")
  }
  // only after commit succeeds:
  UserDefaults.standard.removePersistentDomain(forName: bundleID)
  ```
- Add `UserDefaultsImportTests.swift` covering three fixtures:
  - Empty plist → no-op.
  - Full legacy plist → all rows present, totals match.
  - Partial plist (corrupt one key) → remaining keys still import without raising.
- **Acceptance:** Tests pass. Manual: install v0 build, run, then install SQLite build, verify identical state and emptied `~/Library/Preferences/com.opencode.opencowork.plist`.

### Phase 7 — Validation gate (1h)

| Check | Command | Pass criterion |
|-------|---------|---------------|
| Build | `xcodebuild` | Succeeds. |
| Tests | `xcodebuild test` | 100% pass. |
| Storage growth | Run dummy workload, grow to ~5 MB, reload | Time-to-load < 200 ms; no UI hitch. |
| Concurrency | `testConcurrentWrites` | Passes (covered Phase 3). |
| Migration idempotency | Run import twice | Second run recognizes `user_version == 1` and skips. |
| Privacy | `lsof \| grep store.sqlite` while app idle | Only OpenCowork holds it; no surprises. |
| Crash safety | Kill -9 mid-write of 50 steps | App relaunches with consistent state. |

### Phase 8 — Cleanup (30 min)

- Remove `private let *Key = "com.opencode…"` constants in `AppStore`.
- Remove `oldApproveKey` fallback (no longer needed; everyone migrates).
- Update `implementation.md`: flip M4 row from ⚠️ to ✅, P2 row in Critical Path to ✅.
- Update `proposal.md` §"Technical Architecture": annotate that SQLite storage is in place.

---

## Acceptance Criteria — Ship Readiness

All must be true to merge:

- [ ] `xcodebuild` clean.
- [ ] All tests pass (round-trip + import + concurrency).
- [ ] Migration is crash-safe (proven via test that simulates mid-import crash).
- [ ] No visual change in History / Settings / Skills / Scheduler views.
- [ ] Existing 12 keys in `~/Library/Preferences/com.opencode.opencowork.plist` are removed after first new-build launch.
- [ ] Manual smoke: 5 sessions × 40 steps each can be created, queried by date, and deleted within a single run.
- [ ] Bundle size delta < 2 MB (GRDB static).

---

## Risk Register

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| GRDB Swift 6 strict-concurrency warnings | M | Use `@unchecked Sendable` on the wrapper; suppress per-line as GRDB upstream fixes. |
| One-shot import loses data on partial UserDefaults corruption | M | Importer never throws on a single bad key — logs and skips, continues. |
| Migration race with concurrent `AgentStore` writes on first launch | L | `Database.init` runs before any store is constructed (single static gate). |
| Schema-evolution mistakes later when adding columns | L | Use `DatabaseMigrator` exclusively; never run ad-hoc `ALTER TABLE`. |
| Existing 12 keys become orphan `defaults` after migration | M | Explicit `removePersistentDomain(forName:)` in Phase 6 after commit. |
| WAL mode interaction with Time Machine | L | Time Machine handles WAL files. Document in CHANGELOG. |
| `ValueObservation` streams churn `ObjectWillChange` too often | M | Use `.removeDuplicates()` + debounce at the combine layer. |

---

## Effort Summary (matches the 4–6h estimate from `implementation.md`)

| Phase | Time |
|-------|------|
| 0 — Pre-flight | 0.25h |
| 1 — Add GRDB dep | 0.5h |
| 2 — Database core + schema | 1h |
| 3 — Round-trip + concurrent tests | 1h |
| 4 — CRUD facade + observation streams | 1h |
| 5 — AppStore rewire | 1h |
| 6 — One-shot UserDefaults import | 0.5h |
| 7 — Validation gate | 0.5h |
| 8 — Cleanup + doc updates | 0.25h |
| **Total** | **~5h** |

---

## Out-of-Scope (Deliberately)

- Replacing `FileRollbackManager` with SQLite-backed history (still file-on-disk; SQLite will only record metadata in a follow-up).
- Real-time query UI for "spent by provider this week." Plumbed but not UI'd. Add a v0.2 follow-up.
- Per-project cost aggregation (`Project` ↔ `TaskSession` link). Schema supports it; UI doesn't.
- Windows / Linux port (not a SQLite question — proposal v0.5).
- Sync between machines (privacy promise forbids it without explicit consent; would need a sync layer that's out of scope).
