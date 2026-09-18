#!/bin/sh

set -eu

sanitize_gtk_modules() {
  [ -n "${GTK_MODULES:-}" ] || return 0

  sanitized_modules=""
  old_ifs=$IFS
  IFS=':,'
  # shellcheck disable=SC2086
  set -- $GTK_MODULES
  IFS=$old_ifs

  for module in "$@"; do
    case "$module" in
      "" | canberra-gtk-module | canberra-gtk3-module)
        continue
        ;;
      *)
        if [ -n "$sanitized_modules" ]; then
          sanitized_modules="${sanitized_modules}:${module}"
        else
          sanitized_modules="$module"
        fi
        ;;
    esac
  done

  if [ -n "$sanitized_modules" ]; then
    export GTK_MODULES="$sanitized_modules"
  else
    unset GTK_MODULES
  fi
}

sanitize_gtk_path() {
  [ -n "${GTK_PATH:-}" ] || return 0

  sanitized_path=""
  old_ifs=$IFS
  IFS=':'
  # shellcheck disable=SC2086
  set -- $GTK_PATH
  IFS=$old_ifs

  for path_entry in "$@"; do
    case "$path_entry" in
      "" | *gtk-2.0*)
        continue
        ;;
      *)
        if [ -n "$sanitized_path" ]; then
          sanitized_path="${sanitized_path}:${path_entry}"
        else
          sanitized_path="$path_entry"
        fi
        ;;
    esac
  done

  if [ -n "$sanitized_path" ]; then
    export GTK_PATH="$sanitized_path"
  else
    unset GTK_PATH
  fi
}

sanitize_gtk_modules
sanitize_gtk_path

# Snapped Flutter apps can fail to create an OpenGL context on some
# Pop!_OS/NVIDIA PRIME setups. Default to software rendering for the
# snap and allow advanced users to override it explicitly.
if [ -z "${FLUTTER_LINUX_RENDERER:-}" ]; then
  export FLUTTER_LINUX_RENDERER=software
fi

exec "$@"
