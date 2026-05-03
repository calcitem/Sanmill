// SPDX-License-Identifier: GPL-3.0-or-later
// Game registry — game_id -> rules-factory closure map.
//
// The registry replaces the old hard-coded `build_rules_default` match
// in `api/kernel.rs` so adding a new game becomes:
//
//   1. Implement `GameRules` in the game's crate.
//   2. Register the factory at startup via `register_game(...)`.
//
// Lookups happen exactly once per `tgf_kernel_create*` call (cold
// path), so a `Mutex<HashMap<&'static str, Factory>>` is plenty.  The
// registry is initialised lazily via `OnceLock` and seeded with the
// shipped games (Mill, Othello).

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use tgf_core::GameRules;

/// Factory closure: builds a fresh `Arc<dyn GameRules>` instance.
pub type RulesFactory = fn() -> Arc<dyn GameRules>;

struct Registry {
    factories: Mutex<HashMap<&'static str, RulesFactory>>,
}

impl Registry {
    fn new() -> Self {
        let mut factories = HashMap::new();
        factories.insert(
            "mill",
            (|| Arc::new(tgf_mill::MillRules::default()) as Arc<dyn GameRules>) as RulesFactory,
        );
        factories.insert(
            "othello",
            (|| Arc::new(tgf_othello::OthelloRules::default()) as Arc<dyn GameRules>)
                as RulesFactory,
        );
        Self {
            factories: Mutex::new(factories),
        }
    }
}

fn registry() -> &'static Registry {
    static REGISTRY: OnceLock<Registry> = OnceLock::new();
    REGISTRY.get_or_init(Registry::new)
}

/// Register an additional game factory.  Returns `false` when an
/// entry for `game_id` already exists; the caller should treat the
/// duplicate as a programmer error rather than a recoverable failure.
///
/// Game crates that want to opt into the registry should call this
/// once at startup.  The registry is keyed on `&'static str`, so the
/// id should be a string literal or otherwise have static lifetime.
#[allow(dead_code)] // reserved for downstream game crates
pub fn register_game(game_id: &'static str, factory: RulesFactory) -> bool {
    let r = registry();
    let mut map = r.factories.lock().expect("registry mutex poisoned");
    if map.contains_key(game_id) {
        return false;
    }
    map.insert(game_id, factory);
    true
}

/// Build a fresh `Arc<dyn GameRules>` for `game_id`.  Returns
/// `Err(...)` when the id has not been registered.  The error string
/// is a stable English token the FRB layer surfaces unchanged.
pub fn build_rules(game_id: &str) -> Result<Arc<dyn GameRules>, String> {
    let r = registry();
    let map = r.factories.lock().expect("registry mutex poisoned");
    match map.get(game_id) {
        Some(factory) => Ok(factory()),
        None => Err(format!("unknown game id: {game_id}")),
    }
}

/// List all registered game ids.  Intended for diagnostics / FRB
/// listing endpoints; never used on a hot path.
#[allow(dead_code)] // exposed for tests + diagnostics
pub fn registered_ids() -> Vec<&'static str> {
    let r = registry();
    let map = r.factories.lock().expect("registry mutex poisoned");
    let mut ids: Vec<&'static str> = map.keys().copied().collect();
    ids.sort_unstable();
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shipped_games_are_registered_by_default() {
        let ids = registered_ids();
        assert!(ids.contains(&"mill"));
        assert!(ids.contains(&"othello"));
    }

    #[test]
    fn build_rules_returns_error_for_unknown_id() {
        assert!(build_rules("nonexistent_game").is_err());
    }

    #[test]
    fn build_rules_emits_distinct_instances() {
        // Same game_id should still allocate a fresh Arc each call so
        // mutating one kernel does not affect another.
        let a = build_rules("mill").unwrap();
        let b = build_rules("mill").unwrap();
        assert!(!Arc::ptr_eq(&a, &b));
    }

    #[test]
    fn duplicate_registration_is_rejected() {
        // Use a unique id so the test is order-independent.
        let id: &'static str = "test_dup_game_for_registry";
        let ok = register_game(id, || {
            Arc::new(tgf_mill::MillRules::default()) as Arc<dyn GameRules>
        });
        assert!(ok);
        let again = register_game(id, || {
            Arc::new(tgf_mill::MillRules::default()) as Arc<dyn GameRules>
        });
        assert!(!again);
    }
}
