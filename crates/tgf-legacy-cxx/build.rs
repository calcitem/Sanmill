// SPDX-License-Identifier: GPL-3.0-or-later
// Build script for the transitional C++ bridge.

use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("workspace root")
        .to_path_buf();
    let src = root.join("src");
    let include = root.join("include");
    let perfect = src.join("perfect");

    let mut build = cxx_build::bridge("src/lib.rs");

    build
        .file("cpp/legacy_engine_bridge.cpp")
        .files(
            [
                "bitboard.cpp",
                "mills.cpp",
                "misc.cpp",
                "movegen.cpp",
                "opening_book.cpp",
                "option.cpp",
                "position.cpp",
                "rule.cpp",
            ]
            .into_iter()
            .map(|f| src.join(f)),
        )
        .include(&include)
        .include(&src)
        .include(&perfect)
        .include(root.join("crates"))
        .std("c++17")
        .define("_CRT_SECURE_NO_WARNINGS", None);

    // Perfect database support intentionally remains cxx-bridged.  Compile
    // every perfect/*.cpp here even after the C++ search stack is removed from
    // this transitional bridge.
    let perfect_sources = std::fs::read_dir(&perfect)
        .expect("read src/perfect")
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            (path.extension()?.to_str()? == "cpp").then_some(path)
        })
        .collect::<Vec<_>>();
    build.files(perfect_sources);

    if cfg!(target_env = "msvc") {
        build.flag_if_supported("/utf-8");
        build.flag_if_supported("/EHsc");
        build.flag_if_supported("/wd4267");
        build.flag_if_supported("/wd4244");
        build.flag_if_supported("/wd4100");
        build.flag_if_supported("/wd4189");
    } else {
        build.flag_if_supported("-Wno-unused-parameter");
        build.flag_if_supported("-Wno-sign-compare");
    }

    build.compile("tgf_legacy_cxx_bridge");

    println!("cargo:rerun-if-changed=cpp/legacy_engine_bridge.h");
    println!("cargo:rerun-if-changed=cpp/legacy_engine_bridge.cpp");
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed={}", src.display());
    println!("cargo:rerun-if-changed={}", include.display());
}
