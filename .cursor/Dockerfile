# Image for Cursor Cloud / Background Agents (see .cursor/environment.json).
#
# Flutter SDK version is read from scripts/ensure_flutter.sh at image build time
# (REQUIRED_FLUTTER_VERSION), matching CI workflows and flutter-init.sh.
# Rebuild the agent image after bumping that variable (e.g. ci-upgrade-flutter-version.sh).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        clang-format \
        curl \
        ca-certificates \
        git \
        unzip \
        xz-utils \
        zip \
        xvfb \
        libglu1-mesa \
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
