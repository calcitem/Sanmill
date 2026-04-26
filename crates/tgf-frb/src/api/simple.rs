// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-frb – Phase 1 API surface.
//
// Conventions:
//   - `#[flutter_rust_bridge::frb(sync)]` makes the call synchronous on the
//     Dart side (no Future wrapping); use only for cheap, non-blocking calls.
//   - All public functions in this module are auto-exported to Dart by codegen.

/// FRB required initialisation.  Called once at Flutter app startup before
/// any other TGF function.  Do not remove.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------------------------------------------------------------------
// Phase 1 smoke-check
// ---------------------------------------------------------------------------

/// Returns a greeting string confirming that the Rust → Dart bridge works.
/// Called from Dart as `tgfHelloWorld()` after `await RustLib.init()`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_hello_world() -> String {
    format!(
        "hello from TGF (TabletopGameFramework) v{}",
        env!("CARGO_PKG_VERSION")
    )
}

/// Returns the TGF Rust crate version string.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

// ---------------------------------------------------------------------------
// Phase 2+ API stubs (kernel_create, kernel_apply, …) will be added here.
// ---------------------------------------------------------------------------
