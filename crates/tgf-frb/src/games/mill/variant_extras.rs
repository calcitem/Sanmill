// SPDX-License-Identifier: GPL-3.0-or-later
// Per-handle Mill variant options stashed in the kernel-extras registry.
//
// The framework's session registry only knows that adapters can attach
// `Box<dyn Any + Send + Sync>` payloads to a handle.  This module wraps
// that registry with type-safe Mill helpers so `crate::api::kernel` /
// `crate::api::simple` never need to mention `dyn Any`.

use tgf_mill::MillVariantOptions as NativeMillVariantOptions;

use crate::session_registry::{extras_cloned, put_extras};

/// Strongly-typed extras blob attached to Mill kernel handles.
#[derive(Clone)]
pub(crate) struct MillKernelExtras {
    pub options: NativeMillVariantOptions,
}

/// Attach Mill variant options to `handle` so subsequent search /
/// setup-position calls can pick them up.  Replaces any previously
/// attached extras for the same handle.
pub(crate) fn attach(handle: u32, options: NativeMillVariantOptions) {
    put_extras(handle, MillKernelExtras { options });
}

/// Look up the variant options for a Mill handle, falling back to
/// `MillVariantOptions::default()` when no extras have been attached.
pub(crate) fn options_for(handle: u32) -> NativeMillVariantOptions {
    extras_cloned::<MillKernelExtras>(handle)
        .map(|e| e.options)
        .unwrap_or_default()
}
