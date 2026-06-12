// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// The hot path is generic over `G: Game`; it never stores `dyn GameRules`
// or `dyn Workbench`.  This mirrors the C++ CRTP design in the migration
// plan and keeps do/undo/evaluate calls statically dispatchable.
//
// The crate is internally split into focused submodules so each file
// stays comfortably under ~1000 lines:
//
//   - `result`       — sentinel scores and `SearchResult` POD
//   - `options`      — `SearchAlgorithm`, `SearchPolicy`, `SearchOptions`
//   - `abort`        — cooperative `SearchAbortHandle`
//   - `tt`           — packed clustered transposition table + `SharedTt`
//   - `perft`        — game-neutral leaf counter
//   - `searcher`     — `Searcher<G>`: alpha-beta / PVS / MTD(f) / qsearch
//   - `thread_pool`  — `SearchThreadPool` and `lazy_smp_search`
//   - `mcts`         — `MctsSearcher<G>` UCT scaffold
//
// External callers should keep using the flat `pub use` re-exports
// below; the module split is purely an organisational refactor.

mod abort;
mod mcts;
mod options;
mod perft;
mod result;
mod searcher;
mod thread_pool;
mod tt;

pub use abort::SearchAbortHandle;
pub use mcts::{MctsOptions, MctsResult, MctsSearcher, mcts_search_parallel};
pub use options::{SearchAlgorithm, SearchOptions, SearchPolicy};
pub use perft::{perft, perft_split, perft_unique_keys};
#[allow(deprecated)]
pub use result::MILL_VALUE_UNIQUE;
pub use result::{SearchResult, VALUE_UNIQUE_ROOT_MOVE};
pub use searcher::Searcher;
pub use thread_pool::{LazySmpWorker, SearchThreadPool, lazy_smp_search};
pub use tt::SharedTt;

#[cfg(test)]
mod tests;
