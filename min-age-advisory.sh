#!/usr/bin/env sh
set -eu

MIN_BUN_MAJOR=1
MIN_BUN_MINOR=3
MIN_BUN_PATCH=0

MIN_NPM_MAJOR=11
MIN_NPM_MINOR=10
MIN_NPM_PATCH=0

NPMRC=
BUNFIG=

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

confirm() {
  prompt="$1"

  if [ ! -t 0 ]; then
    info "$prompt [y/N] n"
    info "Non-interactive mode detected; skipping change"
    return 1
  fi

  printf '%s [y/N] ' "$prompt"
  IFS= read -r answer || answer=""

  case "$answer" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

version_part() {
  version="$1"
  part="$2"

  value="$(printf '%s' "$version" | sed 's/^[vV]//' | cut -d. -f"$part" | sed 's/[^0-9].*$//')"

  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac

  printf '%s' "$value"
}

version_lt() {
  version="$1"
  min_major="$2"
  min_minor="$3"
  min_patch="$4"

  major="$(version_part "$version" 1)"
  minor="$(version_part "$version" 2)"
  patch="$(version_part "$version" 3)"

  if [ "$major" -lt "$min_major" ]; then
    return 0
  fi

  if [ "$major" -gt "$min_major" ]; then
    return 1
  fi

  if [ "$minor" -lt "$min_minor" ]; then
    return 0
  fi

  if [ "$minor" -gt "$min_minor" ]; then
    return 1
  fi

  if [ "$patch" -lt "$min_patch" ]; then
    return 0
  fi

  return 1
}

check_npm_version() {
  if ! command -v npm >/dev/null 2>&1; then
    info "npm is not installed; skipping npm version check"
    return 0
  fi

  NPM_VERSION="$(npm --version 2>/dev/null || true)"

  if [ -z "$NPM_VERSION" ]; then
    warn "npm is installed, but its version could not be detected"
    return 0
  fi

  info "npm version: $NPM_VERSION"

  if version_lt "$NPM_VERSION" "$MIN_NPM_MAJOR" "$MIN_NPM_MINOR" "$MIN_NPM_PATCH"; then
    warn "npm min-release-age requires npm ${MIN_NPM_MAJOR}.${MIN_NPM_MINOR}.${MIN_NPM_PATCH} or newer."
    warn "Update npm before relying on min-release-age."
    return 1
  fi

  return 0
}

check_npmrc_min_release_age() {
  npm_min_release_age_supported="$1"

  if [ -f "$NPMRC" ]; then
    if grep -Eq '^[[:space:]]*min-release-age[[:space:]]*=' "$NPMRC"; then
      info ".npmrc already contains min-release-age"
    else
      if [ "$npm_min_release_age_supported" -eq 0 ]; then
        info "You can add this to $NPMRC now, but update npm before relying on it:"
      else
        info "Suggestion: add this to $NPMRC:"
      fi
      info "min-release-age=3"

      if confirm "Apply this change?"; then
        printf '\nmin-release-age=3\n' >> "$NPMRC"
        info "Added min-release-age=3 to $NPMRC"
      else
        info "Skipped .npmrc change"
      fi
    fi
  else
    info "$NPMRC does not exist."
    if [ "$npm_min_release_age_supported" -eq 0 ]; then
      info "You can create ~/.npmrc now, but update npm before relying on it:"
    else
      info "If you ever use npm, consider adding this to ~/.npmrc:"
    fi
    info "min-release-age=3"

    if confirm "Create $NPMRC with this setting?"; then
      printf 'min-release-age=3\n' > "$NPMRC"
      info "Created $NPMRC"
    else
      info "Skipped .npmrc creation"
    fi
  fi
}

bunfig_has_install_minimum_release_age() {
  awk '
    /^[[:space:]]*\[/ {
      in_install = ($0 ~ /^[[:space:]]*\[install\][[:space:]]*$/)
    }
    in_install && /^[[:space:]]*minimumReleaseAge[[:space:]]*=/ {
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  ' "$BUNFIG"
}

check_bunfig_minimum_release_age() {
  if [ ! -f "$BUNFIG" ]; then
    info "$BUNFIG does not exist."
    info "Suggestion: create it with:"
    info "[install]"
    info "minimumReleaseAge = 259200"

    if confirm "Create $BUNFIG with this setting?"; then
      {
        printf '[install]\n'
        printf 'minimumReleaseAge = 259200\n'
      } > "$BUNFIG"
      info "Created $BUNFIG"
    else
      info "Skipped bunfig creation"
    fi

    return 0
  fi

  if bunfig_has_install_minimum_release_age; then
    info "bunfig.toml already contains minimumReleaseAge under [install]"
    return 0
  fi

  info "Suggestion: add this to $BUNFIG:"
  info "[install]"
  info "minimumReleaseAge = 259200"

  if ! confirm "Apply this change?"; then
    info "Skipped bunfig change"
    return 0
  fi

  if grep -Eq '^[[:space:]]*\[install\][[:space:]]*$' "$BUNFIG"; then
    if ! command -v ed >/dev/null 2>&1; then
      warn "Cannot update $BUNFIG directly: ed is not installed."
      return 1
    fi

    install_line="$(
      awk '
      /^[[:space:]]*\[install\][[:space:]]*$/ && !done {
        print NR
        exit
      }
    ' "$BUNFIG"
    )"

    if [ -z "$install_line" ]; then
      warn "Could not locate [install] in $BUNFIG"
      return 1
    fi

    if ! printf '%s\n' \
      "${install_line}a" \
      'minimumReleaseAge = 259200' \
      '.' \
      'w' \
      'q' | ed -s "$BUNFIG" >/dev/null; then
      warn "Failed to update $BUNFIG"
      return 1
    fi
  else
    {
      printf '\n[install]\n'
      printf 'minimumReleaseAge = 259200\n'
    } >> "$BUNFIG"
  fi

  info "Added Bun minimumReleaseAge to $BUNFIG"
}

check_bun() {
  if ! command -v bun >/dev/null 2>&1; then
    info "Bun is not installed; skipping Bun checks"
    return 0
  fi

  BUN_VERSION="$(bun --version 2>/dev/null || true)"

  if [ -z "$BUN_VERSION" ]; then
    warn "Bun is installed, but its version could not be detected"
    return 0
  fi

  info "Bun version: $BUN_VERSION"

  if version_lt "$BUN_VERSION" "$MIN_BUN_MAJOR" "$MIN_BUN_MINOR" "$MIN_BUN_PATCH"; then
    warn "Bun minimumReleaseAge requires Bun ${MIN_BUN_MAJOR}.${MIN_BUN_MINOR}.${MIN_BUN_PATCH} or newer."
    warn "Update Bun immediately."
    exit 1
  fi

  check_bunfig_minimum_release_age
}

main() {
  if [ -z "${HOME:-}" ]; then
    warn "HOME is not set; cannot check user npm/Bun config files"
    exit 1
  fi

  NPMRC="$HOME/.npmrc"
  BUNFIG="$HOME/.bunfig.toml"

  check_bun

  npm_min_release_age_supported=1
  if ! check_npm_version; then
    npm_min_release_age_supported=0
  fi

  check_npmrc_min_release_age "$npm_min_release_age_supported"

  info "Checkup complete"
}

main
