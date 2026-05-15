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

BUN_MINIMUM_RELEASE_AGE_EXCLUDES='@gm/event-hub
@gm/styles
@gm/ui-components
@gm/gm-api-clients-base
@gm/gm-asset-hierachy-api-client
@gm/gm-businessrelations-api-client
@gm/gm-cloud-components
@gm/gm-cloud-e2e-test-base
@gm/gm-cloud-events
@gm/gm-cloud-tenant
@gm/gm-cloud-tenant-tanstack
@gm/gm-cloud-tenant-wouter
@gm/gm-cloud-theme
@gm/gm-coding-conventions
@gm/gm-component-library
@gm/gm-energy-api-client
@gm/gm-kendo-intl
@gm/gm-notifications-api-client
@gm/gm-tasks-api-client
@gm/gm-usermanagement-api-client
@gm/gm-utils'

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

confirm() {
  prompt="$1"

  if [ ! -t 1 ] || [ ! -r /dev/tty ]; then
    info "$prompt [y/N] n"
    info "No interactive terminal detected; skipping change"
    return 1
  fi

  printf '%s [y/N] ' "$prompt" > /dev/tty

  if IFS= read -r answer < /dev/tty; then
    :
  else
    answer=""
  fi

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

toml_array_from_lines() {
  first=1
  printf '['

  printf '%s\n' "$BUN_MINIMUM_RELEASE_AGE_EXCLUDES" | while IFS= read -r package_name; do
    [ -n "$package_name" ] || continue

    escaped="$(printf '%s' "$package_name" | sed 's/\\/\\\\/g; s/"/\\"/g')"

    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ', '
    fi

    printf '"%s"' "$escaped"
  done

  printf ']'
}

bunfig_has_install_key() {
  key="$1"

  awk -v key="$key" '
    /^[[:space:]]*\[/ {
      in_install = ($0 ~ /^[[:space:]]*\[install\][[:space:]]*$/)
    }

    in_install {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line ~ "^" key "[[:space:]]*=") {
        found = 1
      }
    }

    END {
      exit found ? 0 : 1
    }
  ' "$BUNFIG"
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

check_bunfig_minimum_release_age() {
  exclude_line="minimumReleaseAgeExcludes = $(toml_array_from_lines)"

  if [ ! -f "$BUNFIG" ]; then
    info "$BUNFIG does not exist."
    info "Suggestion: create it with:"
    info "[install]"
    info "minimumReleaseAge = 259200"
    info "$exclude_line"

    if confirm "Create $BUNFIG with this setting?"; then
      {
        printf '[install]\n'
        printf 'minimumReleaseAge = 259200\n'
        printf '%s\n' "$exclude_line"
      } > "$BUNFIG"
      info "Created $BUNFIG"
    else
      info "Skipped bunfig creation"
    fi

    return 0
  fi

  has_minimum_release_age=0
  has_minimum_release_age_excludes=0

  if bunfig_has_install_key minimumReleaseAge; then
    has_minimum_release_age=1
  fi

  if bunfig_has_install_key minimumReleaseAgeExcludes; then
    has_minimum_release_age_excludes=1
  fi

  if [ "$has_minimum_release_age" -eq 1 ] && [ "$has_minimum_release_age_excludes" -eq 1 ]; then
    info "bunfig.toml already contains minimumReleaseAge and minimumReleaseAgeExcludes under [install]"
    return 0
  fi

  info "Suggestion: ensure $BUNFIG contains this under [install]:"

  if [ "$has_minimum_release_age" -eq 0 ]; then
    info "minimumReleaseAge = 259200"
  fi

  if [ "$has_minimum_release_age_excludes" -eq 0 ]; then
    info "$exclude_line"
  fi

  if ! confirm "Apply this change?"; then
    info "Skipped bunfig change"
    return 0
  fi

  tmp_file="${BUNFIG}.tmp.$$"

  if grep -Eq '^[[:space:]]*\[install\][[:space:]]*$' "$BUNFIG"; then
    awk \
      -v has_min="$has_minimum_release_age" \
      -v has_excludes="$has_minimum_release_age_excludes" \
      -v exclude_line="$exclude_line" '
      {
        print $0

        if (!inserted && $0 ~ /^[[:space:]]*\[install\][[:space:]]*$/) {
          if (has_min == 0) {
            print "minimumReleaseAge = 259200"
          }

          if (has_excludes == 0) {
            print exclude_line
          }

          inserted = 1
        }
      }
    ' "$BUNFIG" > "$tmp_file" || {
      rm -f "$tmp_file"
      warn "Failed to update $BUNFIG"
      return 1
    }

    mv "$tmp_file" "$BUNFIG"
  else
    {
      printf '\n[install]\n'

      if [ "$has_minimum_release_age" -eq 0 ]; then
        printf 'minimumReleaseAge = 259200\n'
      fi

      if [ "$has_minimum_release_age_excludes" -eq 0 ]; then
        printf '%s\n' "$exclude_line"
      fi
    } >> "$BUNFIG"
  fi

  info "Updated Bun minimumReleaseAge settings in $BUNFIG"
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