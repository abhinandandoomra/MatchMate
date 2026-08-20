# Requirements traceability

Every line of the brief, mapped to where it is implemented and what proves it.

## The brief's own checklist (page 3)

| # | Requirement | Where | Proof |
|---|---|---|---|
| 1 | Page 1 loads; scrolling fetches page 2+ | `MatchListViewModel.rowAppeared(at:)` → `loadNextPage()` | `ViewModelTests.emptyDatabaseFetches`, `prefetchThreshold` |
| 2 | Accept/Decline on **detail** updates it immediately, then the list agrees on back | `ProfileDetailViewModel.apply(_:)` → shared `ProfileRepository` | `ViewModelTests.detailChangeIsVisibleToListImmediately`, `ObservabilityTests.detailWriteInvalidatesList` |
| 3 | Accept/Decline on the **list card** works | `MatchListViewModel.apply(_:uuid:)` | `ViewModelTests.acceptUpdatesRow` |
| 4 | Kill app, reopen — statuses still there | `SwiftDataProfileStore.save()` | `PersistenceDurabilityTests` (real on-disk store, closed and reopened) |
| 5 | Airplane mode — cache shows; actions still work | `loadCached()` never hits the network; writes never touch it | `ProfileRepositoryTests.loadCachedIsOffline`; **manual on device** |
| 6 | Error cases for API / DB / connectivity | `NetworkError`, `PersistenceError`, `ProfileError`, `NetworkMonitor` | `NetworkErrorTests`, `RetryPolicyTests`, `CancellationTests`, `MatchListStateTests` |
| 7 | ViewModel unit tests green | — | 137 tests, 24 suites |

## Must-do list (page 2)

| Requirement | Status |
|---|---|
| SwiftUI list of match cards | ✅ `MatchListView` + `MatchCardView` |
| Pagination against `page` | ✅ derived cursor, `nextPage = max(sourcePage) + 1` |
| Navigation list → detail, actions on both | ✅ `NavigationStack`, ViewModel owns `path: [Route]` |
| Immediate UI update on the acting screen | ✅ reactive-from-DB, sub-millisecond |
| Saved in local DB | ✅ SwiftData |
| Survives app kill | ✅ `PersistenceDurabilityTests` |
| List and detail always agree | ✅ one repository, two computed projections |
| Local DB — Core Data or SwiftData, justified in README | ✅ SwiftData, justified with the measured 3.6 KB portrait size |
| Offline — cached profiles shown | ✅ `loadCached()` |
| Offline — Accept/Decline works | ✅ the write path never touches the network |
| MVVM + repository, thin UI, injected dependencies | ✅ every seam is a protocol; one composition root |
| `URLSession` + `async/await` | ✅ no third-party dependencies |
| Unit tests for the ViewModel | ✅ `ViewModelTests`, `MatchListStateTests`, `DecisionConcurrencyTests` |
| Error handling: API, DB, connectivity | ✅ typed per service, contextual UI |

## Grading areas the brief names

| Area | Weight | What was done |
|---|---|---|
| Architecture / boundaries | 25% | Infrastructure with zero app references; every seam a protocol; domain-free views |
| Offline + DB + status across screens | 25% | DB as sole source of truth; disagreement structurally unrepresentable; durability tested |
| Pagination + list/detail UX | 15% | Derived cursor that cannot desync; stable ordering; contextual error states |
| Code quality | 15% | No literals in views; no `nonisolated(unsafe)` or `@unchecked Sendable`; Swift 6 strict concurrency clean |
| Unit tests | 15% | 137 tests, 95.0% of non-view code |
| README & commit history | 5% | This folder, plus incremental commits |

## Deliberately out of scope

Pull-to-refresh · search / filter / sort · Accepted-Declined tabs · any server write (no
endpoint exists) · auth, onboarding, settings, profile editing · push, deep links, widgets ·
iPad and landscape layouts · localisation beyond English · UI and snapshot tests · DB
eviction · pixel-matching the reference screenshots (the brief explicitly permits improving
the UI).

## Verified API facts

Established by fetching the live API rather than reading documentation.

| Fact | Value |
|---|---|
| Pagination control | Client-owned, 1-based; server returns no cursor |
| Response metadata | `info` = `{seed, results, page, version}` — no total, no next |
| End of data | None — `page=500` still returns results |
| Page stability | Pages 1–3 with the seed returned 30 unique `login.uuid`s, disjoint |
| `picture.large` | 3.6 KB (128×128 JPEG) |
| Distinct portraits site-wide | ~200 — images repeat across profiles |
| `page` semantics | **Not** an offset: `page=2&results=10` shares zero records with the last 10 of `page=1&results=20` |
