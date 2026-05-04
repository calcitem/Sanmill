# Image for Cursor Cloud / Background Agents (see .cursor/environment.json).
#
# Flutter SDK version is read from scripts/ensure_flutter.sh at image build time
# (REQUIRED_FLUTTER_VERSION), matching CI workflows and flutter-init.sh.
# Rebuild the agent image after bumping that variable (e.g. ci-upgrade-flutter-version.sh).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# System packages required to build and run the Flutter Linux desktop
# bundle, the Rust/TGF engine, and to drive end-to-end testing under
# Xvfb in background agents. Notes on a few non-obvious entries:
#   * llvm-18 - provides /usr/lib/llvm-18/bin/ar (and llvm-ar). The
#     clang-18 package alone does not ship the archiver under its
#     private bin directory, which causes "Failed to find any of
#     [llvm-ar, ar]" when Flutter compiles native code.
#   * gstreamer1.0-plugins-base / -good / -tools - runtime plugins
#     required by the audioplayers_linux plugin. Without "playbin"
#     (plugins-base) and the codecs / sinks (plugins-good),
#     AudioPlayer's constructor throws
#     "Not all elements could be created." and the whole bundle
#     aborts before reaching main(). The matching -dev headers are
#     only needed for compilation.
#   * gdb / imagemagick / scrot / xdotool - debugging and screenshot
#     helpers used to diagnose Linux-desktop startup crashes and to
#     capture UI evidence under Xvfb.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        binutils \
        clang \
        llvm-18 \
        pkg-config \
        libssl-dev \
        clang-format \
        cmake \
        curl \
        ca-certificates \
        git \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer1.0-dev \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-tools \
        libgtk-3-dev \
        lld \
        ninja-build \
        unzip \
        xz-utils \
        zip \
        xvfb \
        xdg-user-dirs \
        libglu1-mesa \
        gdb \
        imagemagick \
        scrot \
        xdotool \
    && rm -rf /var/lib/apt/lists/*

# Rust (channel must stay aligned with rust-toolchain.toml).
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain 1.95.0 \
    && rustup component add rustfmt clippy \
    && chmod -R a+w "${RUSTUP_HOME}" "${CARGO_HOME}"

# Flutter stable tarball for Linux (version from project scripts).
COPY scripts/ensure_flutter.sh /tmp/ensure_flutter.sh

RUN set -eux; \
    FLUTTER_VERSION="$(grep 'REQUIRED_FLUTTER_VERSION:=' /tmp/ensure_flutter.sh | head -n1 | sed 's/.*:=//' | tr -d '}"')"; \
    test -n "${FLUTTER_VERSION}"; \
    FLUTTER_CHANNEL=stable; \
    FLUTTER_BASE="https://storage.googleapis.com/flutter_infra_release/releases"; \
    ARCHIVE="flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"; \
    curl -fL "${FLUTTER_BASE}/${FLUTTER_CHANNEL}/linux/${ARCHIVE}" -o /tmp/flutter.tar.xz; \
    mkdir -p /opt; \
    tar -xf /tmp/flutter.tar.xz -C /opt; \
    rm -f /tmp/flutter.tar.xz /tmp/ensure_flutter.sh; \
    chmod -R a+rx /opt/flutter; \
    git config --global --add safe.directory /opt/flutter || true

ENV PATH="/opt/flutter/bin:${PATH}"

RUN flutter config --no-analytics \
    && flutter precache --linux

# Keep the code generator aligned with the Flutter runtime dependency in
# src/ui/flutter_app/pubspec.yaml.
RUN cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
