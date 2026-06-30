// SPDX-License-Identifier: AGPL-3.0-or-later
// Cooperative search abort handle.

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

#[derive(Clone, Debug)]
pub struct SearchAbortHandle {
    pub(crate) flag: Arc<AtomicBool>,
}

impl SearchAbortHandle {
    /// Wrap an existing shared abort flag.  Use this when the caller owns
    /// the `Arc<AtomicBool>` (for example to share one stop signal across
    /// the UCI main thread, a `lazy_smp_search` fan-out, and any future
    /// timer thread) and just needs an opaque handle to expose.
    pub fn from_arc(flag: Arc<AtomicBool>) -> Self {
        Self { flag }
    }

    pub fn request_abort(&self) {
        self.flag.store(true, Ordering::Relaxed);
    }

    pub fn is_aborted(&self) -> bool {
        self.flag.load(Ordering::Relaxed)
    }
}
