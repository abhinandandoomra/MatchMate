# MatchMate

A matrimonial-style iOS app. Profiles are fetched from Random User with real pagination,
shown as cards, and can be Accepted or Declined from both the list and the detail screen.
Decisions persist locally, work offline, and never disagree between the two screens.

---

## Running it

```bash
open MatchMate.xcodeproj      # Xcode 26+
# Scheme: MatchMate → any iOS 18+ simulator → ⌘R
# Tests: ⌘U
```

Command line:

```bash
xcodebuild test -project MatchMate.xcodeproj -scheme MatchMate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES
```

No dependencies, no configuration, no API key. iOS 18.0 deployment target, Swift 6 language
mode with full strict concurrency.

**137 tests in 24 suites, all green.** Verified on the iOS 26.5 simulator, and built and
signed for a physical device (arm64).

---

## Architecture

Generic infrastructure, then one feature slice on top of it.

```
App/                        MatchMateApp — the composition root
Infrastructure/             knows nothing about profiles
  Networking/               HTTPClient · Endpoint · URLSessionHTTPClient
                            RetryPolicy · NetworkError · ImageFetching
  Persistence/              ModelContainerProviding · PersistenceError
  Connectivity/             ConnectivityMonitoring · NetworkMonitor
  Concurrency/              AppClock
Features/Profile/
  Domain/                   Profile · DecisionStatus · ProfileError
  Data/
    Repository/             ProfileRepository (protocol) · ProfileRepositoryImpl
    Remote/                 ProfileAPIService · ProfileDTO · ProfileMapper
    Local/                  ProfileStore (protocol) · SwiftDataProfileStore
                            ProfileEntity · ProfileEntityMapper
  Presentation/
    MatchList/              RenderModels/ · ViewModel/ · View/
    Detail/                 RenderModels/ · ViewModel/ · View/
    Shared/                 RenderModels/ · View/ · Styles/
```

**`Infrastructure/` contains zero references to profiles** — verified by grep, not asserted.
The HTTP client takes its base URL and decoder at construction, so a second API is a second
instance rather than an edit. The whole folder would lift into a Swift package unchanged.

The split is deliberately **asymmetric**: networking has a genuinely reusable core, and for
persistence only container provisioning does. Inventing a generic profile store would have
meant an abstraction with one implementation and no second caller.

### The data path

```
URLSession → URLSessionHTTPClient → ProfileAPIService ────► [ProfileDTO]
                                                                 │ ProfileMapper
SwiftData  → SwiftDataProfileStore ──────────────────────► [Profile]
                                                                 ▼
                                                    ProfileRepositoryImpl
                                                       profiles: [Profile]
                                                                 ▼
                                                            ViewModels
                                                                 │ MatchRowMapper
                                                                 ▼
                                                      MatchRowUIModel → View
```

Every seam is a protocol: `ProfileRepository`, `ProfileStore`, `ProfileAPIServicing`,
`HTTPClient`, `ImageFetching`, `ConnectivityMonitoring`, `AppClock`,
`ModelContainerProviding`. Nothing constructs its own dependencies below the composition
root, which is a single 20-line function in `MatchMateApp.swift`.

**Views are domain-free.** They receive pre-formatted render models and emit
`DecisionIntent` — `.accept` / `.decline` / `.undo` — never a `DecisionStatus`. Translating
intent into domain state is the ViewModel's job.

### Threading

| Runs on | What |
|---|---|
| `@MainActor` | Views, ViewModels, the repository, all Observation |
| `@ModelActor` | Every `ModelContext` operation |
| Task-isolated | HTTP client, retry, image fetching |

`@Model` is `@Observable` but **not** `Sendable`, so `ProfileEntity` never leaves the store
actor — everything crossing that boundary is a `Sendable` value.

---

## Why SwiftData

Chosen over Core Data for materially less boilerplate: no `NSPersistentContainer` setup, no
`NSFetchedResultsController`, no `NSManagedObject` subclasses. The schema is one entity.

The honest trade: because reactivity is driven by the repository rather than `@Query`, much
of SwiftData's SwiftUI integration goes unused and Core Data would have worked equally well.
SwiftData wins on the code you *don't* write.

**`imageData` is stored inline, without `@Attribute(.externalStorage)`.** I measured the
payload: `picture.large` is **3.6 KB**, and external storage only engages above ~128 KB, so
the attribute would be inert. Storing bytes in the row guarantees photos render offline.

---

## How pagination works

The API returns **no cursor and no total**, so the client owns paging. Each profile records
the page it arrived on, and the cursor is *derived*:

```swift
nextPage = max(sourcePage) + 1
```

Because it comes from rows that actually persisted, a failed fetch writes nothing and the
cursor is automatically unchanged — retry requests the same page, and a gap is impossible.
There is no counter to roll back and nothing to keep in sync.

The same two integers give the list a stable order: rows sort by
`(sourcePage, indexInPage)`. Without an explicit sort key SwiftData does not preserve
insertion order and the list reshuffles between launches.

### A constraint worth knowing

`results` is fixed at `10` and must never vary. Verified against the live API — `page` is
**not** an offset into one stream:

| | |
|---|---|
| `page=1&results=10` vs first 10 of `page=1&results=20` | identical ✅ |
| `page=2&results=10` vs last 10 of `page=1&results=20` | **zero overlap** ❌ |

A page's identity is the triple `(seed, results, page)`. Changing `results` re-partitions the
dataset and silently corrupts already-cached pages. It lives on `ProfileAPIConfig.init` with
that reasoning attached, so it cannot be reached and changed from elsewhere.

---

## How status stays in sync

*A decision made on detail must already show on the list when you go back, with no manual
refresh.* This is satisfied structurally, not by synchronisation code.

```
        MatchListViewModel.rows        ProfileDetailViewModel.profile
                 (computed)                     (computed)
                      ↑  ↓                        ↑  ↓
                      └──── ProfileRepository ────┘
                             profiles: [Profile]
                                   ↑  ↓
                                SwiftData
```

Both ViewModels receive the **same** repository and expose **computed** projections of its
single `profiles` array. Neither holds a copy. A write from either screen re-projects that
array and Observation re-renders both. **Disagreement isn't prevented — it's
unrepresentable.**

Writes are reactive-from-database: the tap updates the DB and the UI follows, so the screen
can never show a status the database doesn't hold — which is why the "revert on write
failure" case needs no revert code.

### The invariant that protects decisions

The API has no write endpoint and no status field, so decisions are client-owned. The danger
is a sync overwriting one. The guard is the *absence* of two lines:

```swift
func applyAPIFields(_ profile: Profile, to entity: ProfileEntity) {
    entity.firstName = profile.firstName
    …
    // No entity.statusRaw = … and no entity.decidedAt = …
}
```

Upsert matches on `login.uuid`, refreshes API-owned fields, and leaves user-owned fields
untouched. Re-fetching is therefore safe by construction, and it is tested end to end.

---

## Decisions are reversible

Beyond the brief, which only shows pending → decided. Tapping the status pill emits `.undo`
and returns the profile to undecided; the buttons switch directly. All transitions are
legal, so there are no dead ends.

**Rapid taps are dropped, not queued.** Status is read and written across an `await`, so two
taps landing in that window would both read the old value and race. A per-profile in-flight
set makes the second tap a no-op and the control inert meanwhile — per profile, so deciding
one match never blocks another.

---

## Error handling

Retries live **inside** the network layer, so a call that fails once and then succeeds is
never visible to a ViewModel. Three attempts, 0.5s → 1s → 2s, honouring `Retry-After` on
429, cancellation-aware. The clock is injected, so retry tests run in microseconds instead of
sleeping.

Only transient failures retry: timeouts, 5xx and 429. **A 404 is a stable answer and fails
immediately.** Offline is not retried either — the connectivity monitor already knows. A
cancelled request is classified as `.cancelled` and never shown; before that existed,
scrolling away mid-fetch surfaced to the user as *"The server couldn't be reached."*

Errors are service-owned — `NetworkError` and `PersistenceError` — wrapped by the feature as
`ProfileError`, which keeps the presentation mapper's switch exhaustive. The error types
carry **no user-facing copy**; that lives in `ProfileErrorText` in the presentation layer.

Severity is contextual rather than uniform:

| Situation | Behaviour |
|---|---|
| First load fails, DB empty | Full-screen error + retry |
| First load fails, DB has data | Non-blocking banner over cached content |
| Next page fails | Footer retry; list intact; cursor unchanged |
| Image fails | Locally drawn initials placeholder; retried later |
| DB write fails | UI already mirrors the DB, so nothing to revert |

The list screen exposes a single `MatchListState` — `.loading`, `.empty`, `.failed`,
`.loaded(rows:footer:)` — so the view switches once rather than deriving the rule from four
booleans.

---

## Payload quirks, and why only one needed code

Fetching real data turned up three inconsistencies. Only one cost anything:

| Quirk | Evidence | Response |
|---|---|---|
| `location.postcode` is `Int` or `String` | both within 30 records | **Not decoded** — unused by the domain |
| `id.value` is `null` | ~1 in 4 records | **Not decoded** — `login.uuid` is the key |
| Dates carry fractional seconds | **60 of 60** sampled | **Handled** — these dates are used |

The first two were initially "solved" with a custom decoder and optional wrappers. That was
the wrong instinct: the DTO declares only the fourteen fields the domain consumes,
`Decodable` ignores every other key, and **a field you never read cannot break you no matter
what type it arrives as.** Deleting those declarations removed a decoder, two types and
their tests.

The date quirk is real: `.iso8601` omits `.withFractionalSeconds` and fails on **every
record** on iOS 18. Newer runtimes parse them fine — which makes this easy to "verify" away
on a modern simulator and then break on the oldest OS supported.

---

## Tests

**137 tests in 24 suites**, Swift Testing. No network and no disk in the default path — the
store protocol is stubbed with an in-memory actor, `URLSession` is stubbed via `URLProtocol`,
and persistence suites use an in-memory `ModelContainer`.

| Coverage | |
|---|---|
| **Non-view code** | **95.0%** (900/947 lines) |
| Whole target (Xcode's figure) | 71.1% |

Both are quoted deliberately: SwiftUI view bodies count as code and UI tests were out of
scope, so the whole-target number understates how well the logic is covered.

Three suites worth calling out:

- **`ObservabilityTests`** — reads what a view body reads inside `withObservationTracking`
  and asserts the redraw is triggered. The chain passes through three mappings and a
  protocol existential; if any link stored a mapped result instead of computing it,
  Observation would stop firing with no compiler error and the UI would silently freeze.
- **`PersistenceDurabilityTests`** — writes to a real on-disk store, closes it, and reopens
  from a fresh container. A `@ModelActor`'s context has `autosaveEnabled == false`, so a
  mutation without `save()` is still returned by every in-session read while never reaching
  disk. Only reopening exposes it.
- **`DecisionConcurrencyTests`** — eight overlapping taps produce exactly one write.

The test that proves the core requirement, with no navigation involved:

```swift
await detailVM.apply(.accept)
#expect(detailVM.profile?.decision?.title == "Accepted")   // detail updates immediately
#expect(listVM.rows.first?.decision?.title == "Accepted")  // list already agrees
```

---

## Known gaps

1. **Unbounded growth.** Paging is uncapped and images live in the DB, ~5 KB per profile.
   No eviction policy.
2. **Connectivity is display-only.** Coming back online removes the banner but does not
   retry a page that failed while offline; the user must scroll or tap Retry.
3. **No pull-to-refresh.** Not in the brief, and with a fixed seed it would refresh nothing.
   A warm launch makes zero network calls by design.
4. **No launch refetch**, so a row written partially is never repaired. Acceptable because
   the seed makes the data immutable.
5. **Reversible decisions** exceed the literal brief — a deliberate call.
6. **No UI tests.** The view layer is verified by hand on the simulator.
7. **Verified on iOS 26.5 only.** Deployment target is 18.0, but no 18.x simulator runtime
   was installed, so behaviour there is reasoned about rather than observed.
8. **Layer boundaries are convention.** A single target means "nothing outside `App/`
   imports `Data/`" is enforced by review, not the compiler. Local SPM packages would make it
   structural.

---

## Rough hours

Roughly **10 hours**: about 2.5 on requirements, technical decisions and design; about 2 on
the first working implementation; and about 5.5 on a file-by-file review pass that reshaped
the networking, persistence, error and presentation layers.

Most of the changes in that last phase came from questions rather than a checklist — *why is
this `static`*, *why does the repository refetch everything*, *why doesn't the repository
have a protocol*. Several found real defects. `docs/DECISIONS.md` records what was decided,
what was reversed, and why.
