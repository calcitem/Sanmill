# State and Bridge Parity

Use for rule transitions, state machines, serialization, replay, or native
session boundaries. Select the observables that belong to the declared task.

## Layered comparison

For each identical action or API call, compare:

- initial state and key;
- board contents, side to move, phase, counters, and clocks;
- legal action set, and action order when search equivalence requires it;
- pending removals, captures, and other multi-step actions;
- history, repetition, undo/redo, and reset state;
- terminal outcome and reason;
- serialized representation and state after decoding.

Do not adjudicate a terminal game before a mandatory continuation has
completed. Check both pre-state and post-state, including auxiliary fields
whose stale values can affect the next action.

For protocols, compare accepted commands, output tokens, malformed-input
behavior, reset/stop/undo/shutdown, EOF, draw/resign, and no-move outcomes.
For bridge codecs, compare the shapes the engine emits with the shapes the
frontend accepts; successful parsing alone does not establish semantic parity.

## Reproducers and owning layers

Stop advancing the failing sequence at the first mismatch, then minimize it.
Record the earliest divergent action and complete before/after state.
Do not stop the overall investigation.

Common causes include:

- different post-state: apply/transition, history, or serialization;
- same state but different key: hashing, square mapping, or incremental update;
- bridge-only mismatch: omitted pending state, truncated history, or codec
  assumptions;
- terminal mismatch: adjudication order or a missing mandatory action.

Use apply/undo properties, FEN or snapshot round trips, fixed replay transcripts,
recorded oracle cases, and seeded walks as appropriate. Preserve raw evidence
and distinguish sampled coverage from exhaustive state-space proof.

## Session history

When a compact snapshot cannot hold all runtime history:

1. Preserve the compact format when compatibility requires it.
2. Retain full history in the session and reconstruct bounded search history
   at the session/search boundary.
3. Inject that history into rule application and search-root construction.
4. Keep reconstruction outside the per-node search hot path.
5. Check resets after irreversible actions and after session changes.

Exercise the affected UI, CLI, FRB, replay, and search-root entry points.
A test-harness-only history fix is insufficient when the product path still
drops information.

Preserve saved games, preset identities, Hive fields, and old import formats.
If a migration is required, make it explicit and verify recovery/compatibility
rather than resetting real user data to pass a test.
