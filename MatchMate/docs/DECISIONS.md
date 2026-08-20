# Decisions

What was chosen, what was reversed, and why. Reversals are kept because the reasoning that
overturned a decision is usually more useful than the decision.

---

## Scope

| | Decision | Reasoning |
|---|---|---|
| S-1 | SwiftData over Core Data | Far less boilerplate; the schema is one entity. Core Data would have worked equally well — see README |
| S-2 | iOS 18.0, Swift 6, full strict concurrency | Compiler-enforced data-race safety; forces explicit isolation, which the design needs anyway |
| S-3 | No third-party dependencies | The brief allows them "with a reason"; there wasn't one |
| S-4 | Truly infinite paging, no cap | Matches the API, which returns results at `page=500`. No end state exists to design |
| S-5 | Reversible decisions | Exceeds the literal brief. Deliberate: a real product allows undo, and the state machine has no dead ends |
| S-6 | No pull-to-refresh | Not in the brief, and the fixed seed makes the data immutable. Refreshing would be theatre |
| S-7 | Warm launch makes no network call | *"Do I have cached data?"* and *"does the user need another page?"* are independent questions |

---

## Architecture

### A-1 · The repository is the notification mechanism

`@Model` is `@Observable` but not `Sendable`. Entities cannot leave the store actor, so
reactivity cannot come from `@Model` observation. Alternatives considered: an `AsyncStream`
from the store (continuation lifecycle, leak surface), or `@Query` in views (SwiftData in the
view layer, untestable).

Chosen: a `@MainActor @Observable` repository whose `profiles` array *is* the notification.
Both ViewModels project from it, so list/detail disagreement is unrepresentable rather than
prevented.

### A-2 · Infrastructure separated from feature

Justified by measurement, not taste: eight files were genuinely generic; everything else
carried heavy Profile coupling — `ProfileEntityMapper` alone had 49 references.

Deliberately **asymmetric**: there is no generic profile store, because every persistence
file is Profile-specific. Only container provisioning is reusable. Inventing symmetry would
have produced an abstraction with one implementation and no second caller.

### A-3 · Views are domain-free

Views emit `DecisionIntent` (`.accept` / `.decline` / `.undo`) and receive pre-formatted
render models. No `DecisionStatus` reaches the view layer.

This removed a rule from the views: undo used to work by re-applying the current status and
letting a toggle invert it, which meant a *view* had to know that rule. With explicit intent,
the rule disappeared rather than moved.

### A-4 · Style is injected, not global

`ProfileStyle` is a struct delivered through `@Environment`, not an enum of statics. No view
contains a numeric literal — verified by grep. A restyled variant is one different instance
handed to the root.

---

## Reversals

These were decided one way, then changed. The reasoning is the useful part.

### TD-A · DTO mapping moved out of the domain, then the repository moved instead

**First:** `ProfileAPI` (in `Domain/`) returned `[ProfileDTO]` and `ProfileRepository`
mapped them. **Problem:** the domain layer knew the wire format and called a Data-layer
mapper — an inward-pointing dependency, backwards.

**Fix attempt:** move mapping into `RandomUserAPI` so `fetchPage` returned `[Profile]`.

**Final:** the repository maps, and the *repository* moved to `Data/`. A type that knows the
wire format belongs on the data side of the line; `Domain/` is now three files.

Residual asymmetry, accepted knowingly: the local store converts to domain (it must —
entities are not `Sendable`), while the remote source returns DTOs and the repository
converts. Both are defensible; they are not both true at once.

### TD-B · Repository protocol added after being argued against

I initially argued against a repository protocol on the grounds that Observation through an
existential was risky, and that it was the one mechanism list/detail consistency rested on.

That was over-cautious, and testing settled it: `Observable` **is** a protocol, so
`protocol ProfileRepository: AnyObject, Observable` makes conformance a compiler
requirement, and reading through the existential still trips the observation registrar.
Verified before adopting.

### TD-C · Three "API hazards" became one

`postcode` (`Int` or `String`) and `id.value` (`null`) were handled with a custom
`FlexibleString` decoder and optional wrappers. Then: **neither field is used by the
domain.** `Decodable` ignores undeclared keys, so not declaring a field is strictly stronger
than decoding it defensively — no strategy can fail on a key that is never read.

Deleted a decoder, two types and five tests. Only the fractional-seconds date quirk was real,
because those values *are* used.

### TD-D · `save()` kept after being challenged

Proposal: mutate the entity and skip `save()` and the refresh. Tested it:

```
autosaveEnabled = false          ← a @ModelActor's context does not autosave
in-context read  = "accepted"    ← the app looks entirely correct
after reopen     = pending       ← the write never reached disk
```

The write is visible to every in-session read and silently never persists. `save()` stays,
and `PersistenceDurabilityTests` now guards it — the first coverage of *"kill app, reopen."*

The other half of the proposal was right, though: the **refresh** was redundant, and removing
it is TD-E.

### TD-E · Writes stopped re-reading the table

Every mutation used to call `refresh()`, re-reading and re-mapping the whole store. Measured
against a real store:

| profiles | write | full re-read |
|---|---|---|
| 10 | 0.32 ms | 0.31 ms |
| 100 | 0.30 ms | 2.37 ms |
| 500 | 0.31 ms | **14.44 ms** |

At 500 profiles the refresh cost **46× the write it was reporting**, and the UI waited on it.
Now the store returns the rows it persisted and the repository merges them: **0.29 ms flat.**

Crucially the store stays the authority on the resulting state — echoing back the argument
would have reported `.pending` for a profile the user had already accepted, because upsert
deliberately preserves decisions.

---

## Concurrency

| | Decision |
|---|---|
| C-1 | Retry lives inside the network layer, with an injected clock. A call that fails once then succeeds is never visible above it, and retry tests run in microseconds |
| C-2 | Only transient failures retry. A 404 is a stable answer; retrying burns the budget and delays the error the user needs |
| C-3 | `NetworkError.cancelled` exists because `URLSession` reports cancellation as a `URLError`, which the default mapping swept into `.server(status: -1)`. Scrolling away mid-fetch showed *"The server couldn't be reached."* |
| C-4 | Rapid decision taps are dropped, not queued — status is read and written across an `await`, so two taps in that window would race. Per-profile, so one match never blocks another |
| C-5 | `NetworkMonitor` uses a lock rather than an actor: `pathUpdateHandler` is synchronous, and hopping to an actor from it would let two path updates land out of order |

---

## Things a reviewer might reasonably challenge

- **Four models and four mappers** for a ~20-file app. Justified by testability — every
  mapper is a pure function — but it is more code than three would be.
- **The `Domain/` layer is thin.** Three files, with the seam protocols in `Data/`. A
  consequence of TD-A, not an accident.
- **`Presentation` depends on `Data/`** for the repository protocol, rather than on a
  domain-level abstraction. Conventional in practice; not textbook.
- **Connectivity is display-only** — it draws a banner but does not trigger recovery.
- **No UI tests**, so the view layer rests on manual verification.
