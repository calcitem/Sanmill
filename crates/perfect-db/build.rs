// SPDX-License-Identifier: GPL-3.0-or-later

use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let csrc = manifest_dir.join("csrc");

    let sources = [
        "perfect_api.cpp",
        "perfect_c_api.cpp",
        "perfect_common.cpp",
        "perfect_debug.cpp",
        "perfect_errors.cpp",
        "perfect_eval_elem.cpp",
        "perfect_game.cpp",
        "perfect_game_state.cpp",
        "perfect_hash.cpp",
        "perfect_init.cpp",
        "perfect_log.cpp",
        "perfect_move.cpp",
        "perfect_player.cpp",
        "perfect_rules.cpp",
        "perfect_sec_val.cpp",
        "perfect_sector.cpp",
        "perfect_sector_graph.cpp",
        "perfect_symmetries.cpp",
        "perfect_symmetries_slow.cpp",
        "perfect_wrappers.cpp",
        "option.cpp",
        "rule.cpp",
    ];

    let mut build = cc::Build::new();
    build.cpp(true).std("c++17").include(&csrc).warnings(false);

    if cfg!(target_env = "msvc") {
        build.flag("/EHsc");
    } else {
        build.flag_if_supported("-Wno-unused-parameter");
        build.flag_if_supported("-Wno-sign-compare");
    }

    for src in sources {
        build.file(csrc.join(src));
    }

    build.compile("perfect_db");

    let target = env::var("TARGET").expect("TARGET");
    if target.contains("android") {
        println!("cargo:rustc-link-lib=c++_shared");
    }
}
