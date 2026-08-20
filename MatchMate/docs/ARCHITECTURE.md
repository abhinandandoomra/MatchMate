# Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  App/            MatchMateApp — the composition root         │
└───────────────────────────┬──────────────────────────────────┘
                            │ builds, once, at launch
┌───────────────────────────▼──────────────────────────────────┐
│  Features/Profile/Presentation                               │
│    RenderModels/  MatchRowUIModel · DecisionBadge · Intent    │
│    ViewModel/     MatchListViewModel · ProfileDetailViewModel │
│    View/          SwiftUI, domain-free                        │
│    Styles/        ProfileStyle, injected via Environment      │
└───────────────────────────┬──────────────────────────────────┘
                            │ any ProfileRepository
┌───────────────────────────▼──────────────────────────────────┐
│  Features/Profile/Data                                       │
│    Repository/    ProfileRepository · ProfileRepositoryImpl   │
│    Remote/        ProfileAPIService · DTOs · ProfileMapper    │
│    Local/         ProfileStore · SwiftDataProfileStore        │
└───────────────────────────┬──────────────────────────────────┘
                            │ Profile · DecisionStatus · ProfileError
┌───────────────────────────▼──────────────────────────────────┐
│  Features/Profile/Domain    models and failure vocabulary     │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Infrastructure/   zero references to profiles                │
│    Networking · Persistence · Connectivity · Concurrency      │
└──────────────────────────────────────────────────────────────┘
```

`Domain/` is deliberately thin — three files. The seam protocols live beside their
implementations in `Data/`, because the repository maps DTOs and therefore belongs on the
data side of the line. That is a departure from textbook Clean Architecture, taken
knowingly: see `DECISIONS.md`, TD-B.

## Key flows

### Cold launch, empty store

```
.task → onAppear() → loadCached()      → store empty
                   → loadNextPage()    → api.profiles(page: 1)
                                       → ProfileMapper → [Profile]
                                       → store.upsert → returns persisted rows
                                       → merge into repo.profiles
                                       → Observation → list renders
                   → image backfill    → TaskGroup, 10 × 3.6 KB → merge
```

### Warm launch

```
.task → onAppear() → loadCached()      → rows from disk, rendered immediately
                                       → nextPage = max(sourcePage) + 1
                                       → NO network call
```

*"Do I have cached data to display?"* and *"does the user need another page?"* are two
independent decisions, not one branch. A non-empty store suppresses the launch fetch; it
does not suppress paging.

### A decision, from either screen

```
tap → DecisionIntent → ViewModel.apply → repository.setStatus
                                       → store writes one row, returns it
                                       → repo.profiles[index] = updated
                                       → Observation → both screens re-render
```

No full re-read. Measured: 0.29 ms flat at 10, 100 and 500 profiles. Before the store
returned the persisted row, this path re-read and re-mapped the entire table — 15 ms at 500
profiles, a dropped frame per tap, growing linearly.

### Pagination failure

```
api.profiles(page:) throws after 3 attempts
  → nothing persisted
  → max(sourcePage) unchanged
  → nextPage unchanged
  → footer shows retry; the same page is requested again
```

The cursor is a property of the rows that exist, so a gap is not representable.

## The three invariants

| | Invariant | Enforced by |
|---|---|---|
| **R-1** | The network never writes `status` or `decidedAt` | `ProfileEntityMapper.applyAPIFields` simply does not mention them — the rule is a function body, not a comment |
| **C-1** | `results` is always 10 | `ProfileAPIConfig.init(pageSize:)`, with the reasoning attached; unreachable from elsewhere |
| **D-1** | The UI reads only from the store | Views read ViewModels → `repo.profiles` → `store.profiles()`. There is no other source |

## Concurrency model

| Isolation | Types |
|---|---|
| `@MainActor` | Views, ViewModels, `ProfileRepositoryImpl`, Observation |
| `@ModelActor` | `SwiftDataProfileStore` — all `ModelContext` access |
| `Sendable`, task-isolated | `URLSessionHTTPClient`, `RetryPolicy`, `HTTPImageFetcher`, `ProfileAPIService` |
| Lock-guarded | `NetworkMonitor` — `NWPathMonitor` fires a synchronous callback, and hopping to an actor from it would let two path updates land out of order |

The codebase contains **no `nonisolated(unsafe)` and no `@unchecked Sendable`** in app code.

`@Model` is `@Observable` but not `Sendable`, which is the constraint the whole design turns
on: `ProfileEntity` cannot leave the store actor, so reactivity cannot come from `@Model`
observation. It comes from the repository instead.

## Why the repository is the notification mechanism

Both ViewModels hold the same `any ProfileRepository` and expose **computed** projections:

```swift
var rows: [MatchRowUIModel] { repo.profiles.map { mapper.map($0) } }
```

Computed, never stored. Storing the mapped result would break Observation silently — no
compiler error, no crash, just a list that stops updating. `ObservabilityTests` guards this
by reading what a view body reads inside `withObservationTracking`.

The protocol is constrained `: AnyObject, Observable`, so *any* conformer must be
`@Observable`. That turns the requirement from a convention into a compiler guarantee.

## Testing seams

| Seam | Production | Test |
|---|---|---|
| `ProfileStore` | `SwiftDataProfileStore` | `StubProfileStore` (actor over an array) |
| `ProfileAPIServicing` | `ProfileAPIService` | `StubProfileAPI` |
| `HTTPClient` | `URLSessionHTTPClient` | real client + `StubURLProtocol` |
| `AppClock` | `SystemClock` | `StubClock` — retry tests finish in microseconds |
| `ConnectivityMonitoring` | `NetworkMonitor` | `StubConnectivity` |
| `ModelContainerProviding` | `SwiftDataContainerProvider` | in-memory, or a failing provider |

`StubURLProtocol` keys its state per session token rather than statically, because Swift
Testing runs suites in parallel and a shared queue lets concurrent tests consume each
other's responses.
