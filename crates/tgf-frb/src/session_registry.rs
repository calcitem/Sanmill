// SPDX-License-Identifier: GPL-3.0-or-later
// Game-neutral kernel session registry shared by every FRB entry point.
//
// The registry owns a global `HashMap<u32, GameKernel>` keyed by an
// integer handle, and a parallel "extras" map where game-specific FRB
// adapters can stash per-handle data (e.g. Mill variant options) without
// littering the framework-level kernel module with game knowledge.

use std::any::Any;
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU32, Ordering};

use once_cell::sync::Lazy;
use tgf_core::GameKernel;

/// Global kernel registry.  Each Dart-side session is identified by an
/// integer handle issued by [`insert_kernel`].
static KERNELS: Lazy<Mutex<HashMap<u32, GameKernel>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static NEXT_KERNEL_ID: AtomicU32 = AtomicU32::new(1);

/// Per-handle, type-erased extras the concrete game adapters can attach.
/// Mill stores its `MillVariantOptions`; future games can store their own
/// blobs here without modifying the framework registry.
static KERNEL_EXTRAS: Lazy<Mutex<HashMap<u32, Box<dyn Any + Send + Sync>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

/// Insert a freshly-built kernel and return its FRB handle.
pub(crate) fn insert_kernel(kernel: GameKernel) -> u32 {
    let id = NEXT_KERNEL_ID.fetch_add(1, Ordering::SeqCst);
    KERNELS
        .lock()
        .expect("kernel registry poisoned")
        .insert(id, kernel);
    id
}

/// Drop the kernel and any adapter-attached extras for `handle`.
/// Idempotent: missing handles are silently ignored.
pub(crate) fn remove_kernel(handle: u32) {
    KERNELS
        .lock()
        .expect("kernel registry poisoned")
        .remove(&handle);
    KERNEL_EXTRAS
        .lock()
        .expect("kernel extras poisoned")
        .remove(&handle);
}

/// Run `f` against the kernel for `handle`, returning a stable error
/// string if the registry no longer contains the requested session.
pub(crate) fn with_kernel<R>(
    handle: u32,
    f: impl FnOnce(&mut GameKernel) -> R,
) -> Result<R, String> {
    let mut guard = KERNELS.lock().expect("kernel registry poisoned");
    let kernel = guard
        .get_mut(&handle)
        .ok_or_else(|| format!("invalid kernel handle: {handle}"))?;
    Ok(f(kernel))
}

/// Attach typed extras to `handle`.  Replaces any previously attached
/// value; concrete games are expected to use one type per game.
pub(crate) fn put_extras<T: Any + Send + Sync>(handle: u32, value: T) {
    KERNEL_EXTRAS
        .lock()
        .expect("kernel extras poisoned")
        .insert(handle, Box::new(value));
}

/// Read a clone of the typed extras for `handle`, or `None` when the
/// stored type does not match `T`.
pub(crate) fn extras_cloned<T: Any + Clone + Send + Sync>(handle: u32) -> Option<T> {
    let guard = KERNEL_EXTRAS.lock().expect("kernel extras poisoned");
    guard
        .get(&handle)
        .and_then(|boxed| boxed.downcast_ref::<T>())
        .cloned()
}
