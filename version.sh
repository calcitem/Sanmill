#!/bin/bash

# Stamp the Flutter app build number into pubspec.yaml.
#
# The build number is the total git commit count, so every commit yields a
# monotonically increasing value (e.g. 7.4.4+6145).  The base version
# (X.Y.Z) is taken from the existing pubspec.yaml entry.
#
# This script no longer generates the former C++ "include/version.h" header:
# the native C++ engine and Qt UI were removed, and the Rust engine reports
# its own version via env!("CARGO_PKG_VERSION").  The Flutter "About" page
# shows the app version (pubspec) plus the git revision packaged by
# flutter-init.sh (assets/files/git-revision.txt), none of which depend on a
# generated header.

PUBSPEC_YAML_FILE=src/ui/flutter_app/pubspec.yaml

# Define sed command, use gsed on macOS
SED=sed
if [ "$(uname)" == "Darwin" ]; then
	SED=gsed
fi

# Extract base app version from pubspec.yaml (X.Y.Z)
PUBSPEC_VERSION_LINE="$($SED -n 's/^version:[[:space:]]*//p' ${PUBSPEC_YAML_FILE} | head -n 1)"
APP_BASE_VERSION="${PUBSPEC_VERSION_LINE%%+*}"
if [ -z "$APP_BASE_VERSION" ]; then
	echo "Error: Missing version in ${PUBSPEC_YAML_FILE}"
	exit 1
fi

# Use the total git commit count as the build number
APP_BUILD_NUMBER="$(git rev-list HEAD | wc -l | awk '{print $1}')"

# Set app version with build number (total commit count)
APP_VERSION="${APP_BASE_VERSION}+${APP_BUILD_NUMBER}"

# Print the resulting app version
echo "App Version: ${APP_VERSION}"

# Remove the version line from the pubspec.yaml file and insert the new version
$SED -i '/version:/d' ${PUBSPEC_YAML_FILE}
$SED -i "4i\version: ${APP_VERSION}" ${PUBSPEC_YAML_FILE}
