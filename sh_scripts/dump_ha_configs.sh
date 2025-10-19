#!/usr/bin/env bash
# ================================================
# Script: dump_ha_configs.sh
# Location: /config/sh_scripts/
# Version: v1.9.0 — Single-file dump (YAML + Shell + Registry + Entity XREF)
# ================================================

set -euo pipefail

# ---------- toggles (override via env) ----------
INCLUDE_YAML="${INCLUDE_YAML:-1}"                         # include all *.yaml/*.yml
INCLUDE_SH="${INCLUDE_SH:-1}"                             # include /config/sh_scripts/*.sh
INCLUDE_STORAGE_LOVELACE="${INCLUDE_STORAGE_LOVELACE:-0}" # include whitelisted .storage lovelace files
INCLUDE_REGISTRY="${INCLUDE_REGISTRY:-1}"                 # append core.*_registry + config_entries
INCLUDE_GIT="${INCLUDE_GIT:-0}"                           # append git status
MAKE_TARBALL="${MAKE_TARBALL:-0}"                         # tar.gz of YAML files
MAKE_ENTITY_XREF="${MAKE_ENTITY_XREF:-1}"                 # YAML refs → registry cross-walk
SINGLE_FILE_ONLY="${SINGLE_FILE_ONLY:-1}"                 # 1 = no sidecars, append everything to main
KEEP_OLD="${KEEP_OLD:-20}"                                # retain last N dumps in _old/

# Pinned files/dirs we ALWAYS show first (critical for audio audits)
PINNED_FILES_DEFAULT="/config/configuration.yaml /config/automations.yaml /config/scripts.yaml /config/scenes.yaml"
PINNED_DIRS_DEFAULT="/config/packages /config/templates"
PINNED_FILES="${PINNED_FILES:-$PINNED_FILES_DEFAULT}"
PINNED_DIRS="${PINNED_DIRS:-$PINNED_DIRS_DEFAULT}"

# Storage-mode Lovelace (UI) files (safe subset)
STORAGE_WHITELIST="${STORAGE_WHITELIST:-/config/.storage/lovelace /config/.storage/lovelace_dashboards /config/.storage/lovelace_resources}"

DATE="$(date +%m_%d_%Y)"
DUMP_DIR="/config/sh_scripts"
OLD_DIR="$DUMP_DIR/_old"
VERSION_TRACKER="$DUMP_DIR/ha_config_versions.log"
STORAGE_DIR="/config/.storage"

mkdir -p "$DUMP_DIR" "$OLD_DIR"

# ---------- determine version for today ----------
LAST_FROM_TRACKER="$(grep -F "$DATE" "$VERSION_TRACKER" 2>/dev/null | sed -E 's/.*_v([0-9]+)\.txt/\1/' | sort -n | tail -n1 || true)"
LAST_FROM_FILES="$({ find "$DUMP_DIR" -maxdepth 1 -type f -name "ha_config_dump-${DATE}_v*.txt" 2>/dev/null; find "$OLD_DIR" -maxdepth 1 -type f -name "ha_config_dump-${DATE}_v*.txt" 2>/dev/null; } | sed -E 's/.*_v([0-9]+)\.txt/\1/' | sort -n | tail -n1 || true)"
LAST_VERSION="${LAST_FROM_TRACKER:-}"
if [[ -z "${LAST_VERSION}" || "${LAST_FROM_FILES:-0}" -gt "${LAST_VERSION:-0}" ]]; then LAST_VERSION="${LAST_FROM_FILES:-${LAST_VERSION:-}}"; fi
NEXT_VERSION=$(( ${LAST_VERSION:-0} + 1 ))

BASENAME="ha_config_dump-${DATE}_v${NEXT_VERSION}"
OUTPUT_FILE="$DUMP_DIR/${BASENAME}.txt"
ENTITY_LIST_FILE="$DUMP_DIR/${BASENAME}.entities.txt"
YAML_REFS_FILE="$DUMP_DIR/${BASENAME}.yaml_refs.txt"
XREF_REPORT_FILE="$DUMP_DIR/${BASENAME}.xref_report.txt"

echo "🛠 Archiving previous config dumps..."
find "$DUMP_DIR" -maxdepth 1 -type f -name 'ha_config_dump-*.txt' -exec mv {} "$OLD_DIR/" \; || true
ls -t "$OLD_DIR"/ha_config_dump-*.txt 2>/dev/null | tail -n +$((KEEP_OLD+1)) | xargs -r rm

echo "📦 Creating config snapshot: $OUTPUT_FILE"
: > "$OUTPUT_FILE"

# ---------- collect pinned lists ----------
PINNED_LIST=()
for f in $PINNED_FILES; do [[ -f "$f" ]] && PINNED_LIST+=("$f"); done
for d in $PINNED_DIRS; do
  if [[ -d "$d" ]]; then
    while IFS= read -r -d '' yf; do PINNED_LIST+=("$yf"); done < <(find "$d" -type f \( -iname "*.yaml" -o -iname "*.yml" \) -print0)
  fi
done
IFS=$'\n' read -r -d '' -a PINNED_LIST < <(printf "%s\n" "${PINNED_LIST[@]}" | sort -u && printf '\0')

# ---------- collect general YAML list ----------
YAML_FILES=()
if [[ "$INCLUDE_YAML" == "1" ]]; then
  mapfile -t YAML_FILES < <(
    find /config -type f \( -iname "*.yaml" -o -iname "*.yml" \) \
      -not -path "/config/.storage/*" \
      -not -path "/config/deps/*" \
      -not -name "secrets.yaml" \
      | sort
  )
fi
# remove any pinned from general list
if [[ "${#PINNED_LIST[@]}" -gt 0 && "${#YAML_FILES[@]}" -gt 0 ]]; then
  TMP=()
  for f in "${YAML_FILES[@]}"; do
    if ! printf "%s\n" "${PINNED_LIST[@]}" | grep -qx "$f"; then TMP+=("$f"); fi
  done
  YAML_FILES=("${TMP[@]}")
fi

# ---------- shell files ----------
SH_FILES=()
if [[ "$INCLUDE_SH" == "1" && -d /config/sh_scripts ]]; then
  mapfile -t SH_FILES < <(find /config/sh_scripts -maxdepth 1 -type f -name "*.sh" | sort)
fi

# ---------- storage-mode lovelace ----------
STORAGE_FILES=()
if [[ "$INCLUDE_STORAGE_LOVELACE" == "1" ]]; then
  for f in $STORAGE_WHITELIST; do [[ -f "$f" ]] && STORAGE_FILES+=("$f"); done
fi

# ---------- header ----------
TOTAL_PINNED=${#PINNED_LIST[@]}
TOTAL_YAML=${#YAML_FILES[@]}
TOTAL_SH=${#SH_FILES[@]}
TOTAL_STORAGE=${#STORAGE_FILES[@]}
{
  echo "=================================================="
  echo " Home Assistant Config Dump (Single File Mode: $SINGLE_FILE_ONLY)"
  echo " Version file: ${BASENAME}.txt"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Sections:"
  echo "  - PINNED files/dirs (audio-critical): $TOTAL_PINNED"
  echo "  - YAML/YML files: $TOTAL_YAML (INCLUDE_YAML=$INCLUDE_YAML)"
  echo "  - Shell scripts:  $TOTAL_SH  (INCLUDE_SH=$INCLUDE_SH)"
  echo "  - .storage (lovelace): $TOTAL_STORAGE (INCLUDE_STORAGE_LOVELACE=$INCLUDE_STORAGE_LOVELACE)"
  echo "  - Registry append: $INCLUDE_REGISTRY"
  echo "  - Entity cross-walk: $MAKE_ENTITY_XREF"
  echo "=================================================="
  echo
  echo "Index — PINNED:"; for f in "${PINNED_LIST[@]}"; do echo " - $f"; done; echo
  echo "Index — YAML:"; for f in "${YAML_FILES[@]}"; do echo " - $f"; done; echo
  echo "Index — Shell scripts:"; for f in "${SH_FILES[@]}"; do echo " - $f"; done; echo
  echo "Index — .storage (lovelace):"; for f in "${STORAGE_FILES[@]}"; do echo " - $f"; done; echo
} >> "$OUTPUT_FILE"

progress_bar() {
  local current="$1" total="$2"
  local denom=$(( total == 0 ? 1 : total ))
  local progress=$((current * 100 / denom))
  local filled=$((progress * 40 / 100))
  local bar="$(printf "%${filled}s" | tr ' ' '#')$(printf "%$((40-filled))s")"
  echo -ne "\r🔄 Progress: [${bar}] ${progress}%"
}

dump_file () {
  local file="$1"
  {
    echo
    echo "=================================================="
    echo "📄 File: $file"
    echo "=================================================="
    echo
    cat "$file" 2>/dev/null || true
    echo
  } >> "$OUTPUT_FILE"
}

# ---------- dump PINNED then YAML ----------
if [[ "$TOTAL_PINNED" -gt 0 ]]; then
  echo "===== BEGIN PINNED (audio-critical) =====" >> "$OUTPUT_FILE"
  i=0; for f in "${PINNED_LIST[@]}"; do dump_file "$f"; i=$((i+1)); progress_bar "$i" "$TOTAL_PINNED"; done
  echo -e "\n===== END PINNED =====\n" >> "$OUTPUT_FILE"
fi

if [[ "$INCLUDE_YAML" == "1" && "$TOTAL_YAML" -gt 0 ]]; then
  echo "===== BEGIN YAML/YML CONTENTS =====" >> "$OUTPUT_FILE"
  i=0; for f in "${YAML_FILES[@]}"; do dump_file "$f"; i=$((i+1)); progress_bar "$i" "$TOTAL_YAML"; done
  echo -e "\n===== END YAML/YML CONTENTS =====\n" >> "$OUTPUT_FILE"
fi

# ---------- dump Shell scripts ----------
if [[ "$INCLUDE_SH" == "1" && "$TOTAL_SH" -gt 0 ]]; then
  echo "===== BEGIN SHELL SCRIPTS =====" >> "$OUTPUT_FILE"
  for shf in "${SH_FILES[@]}"; do
    echo -e "\n----- $shf -----" >> "$OUTPUT_FILE"
    sed -n '1,400p' "$shf" 2>/dev/null >> "$OUTPUT_FILE" || true
  done
  echo -e "\n===== END SHELL SCRIPTS =====\n" >> "$OUTPUT_FILE"
fi

# ---------- dump selected .storage lovelace files ----------
if [[ "$INCLUDE_STORAGE_LOVELACE" == "1" && "$TOTAL_STORAGE" -gt 0 ]]; then
  echo "===== BEGIN .storage (lovelace) =====" >> "$OUTPUT_FILE"
  for jf in "${STORAGE_FILES[@]}"; do
    echo -e "\n----- $jf -----" >> "$OUTPUT_FILE"
    sed -n '1,800p' "$jf" | grep -Ev '"(access_token|refresh_token|client_secret|cloudhook_url|webhook_id)"' >> "$OUTPUT_FILE" || true
  done
  echo -e "\n===== END .storage (lovelace) =====\n" >> "$OUTPUT_FILE"
fi

# ---------- append registry snapshots + build entity list ----------
if [[ "$INCLUDE_REGISTRY" == "1" && -d "$STORAGE_DIR" ]]; then
  echo "===== BEGIN .storage (registry snapshots) =====" >> "$OUTPUT_FILE"
  for jf in core.entity_registry core.device_registry core.area_registry core.config_entries; do
    if [[ -f "$STORAGE_DIR/$jf" ]]; then
      echo -e "\n----- .storage/$jf -----" >> "$OUTPUT_FILE"
      grep -Ev '"(access_token|refresh_token|client_secret|cloudhook_url|webhook_id)"' "$STORAGE_DIR/$jf" >> "$OUTPUT_FILE" || true
    fi
  done
  echo -e "\n===== END .storage (registry snapshots) =====\n" >> "$OUTPUT_FILE"

  # Build flat entity list
  : > "$ENTITY_LIST_FILE"
  if command -v jq >/dev/null 2>&1 && [[ -f "$STORAGE_DIR/core.entity_registry" ]]; then
    jq -r '.data.entities[] | .entity_id' "$STORAGE_DIR/core.entity_registry" | sort -u > "$ENTITY_LIST_FILE"
  elif [[ -f "$STORAGE_DIR/core.entity_registry" ]]; then
    grep -oE '"entity_id":\s*"[^"]+"' "$STORAGE_DIR/core.entity_registry" | sed -E 's/.*"entity_id":\s*"([^"]+)".*/\1/' | sort -u > "$ENTITY_LIST_FILE"
  fi
fi

# ---------- optional: YAML→Registry entity cross-walk ----------
if [[ "$MAKE_ENTITY_XREF" == "1" ]]; then
  : > "$YAML_REFS_FILE"
  if [[ "${#PINNED_LIST[@]}" -gt 0 || "${#YAML_FILES[@]}" -gt 0 ]]; then
    DOMAINS='automation|binary_sensor|button|camera|climate|cover|device_tracker|fan|group|input_boolean|input_button|input_datetime|input_number|input_select|input_text|light|lock|media_player|number|person|remote|scene|script|select|sensor|switch|timer|vacuum|water_heater|weather|zone'
    grep -Eoh "(${DOMAINS})\.[A-Za-z0-9_]+" "${PINNED_LIST[@]}" "${YAML_FILES[@]}" 2>/dev/null \
      | sort -u \
      | grep -Ev '\.yaml$' \
      | grep -Ev '^(script|scene|switch|light|media_player|fan|input_boolean)\.(turn_on|turn_off|toggle|select_source|volume_set|volume_mute)$' \
      > "$YAML_REFS_FILE" || true
  fi

  if [[ -s "$ENTITY_LIST_FILE" && -s "$YAML_REFS_FILE" ]]; then
    comm -23 <(sort "$YAML_REFS_FILE") <(sort "$ENTITY_LIST_FILE") > "$XREF_REPORT_FILE" || true
  fi

  # In single-file mode, append the lists directly and (optionally) remove sidecars
  if [[ "$SINGLE_FILE_ONLY" == "1" ]]; then
    {
      echo "===== BEGIN ENTITY LIST (.storage/core.entity_registry) ====="
      [[ -s "$ENTITY_LIST_FILE" ]] && sed -n '1,99999p' "$ENTITY_LIST_FILE" || echo "(none)"
      echo "===== END ENTITY LIST ====="
      echo
      echo "===== BEGIN YAML ENTITY REFS (grep across YAML) ====="
      [[ -s "$YAML_REFS_FILE" ]] && sed -n '1,99999p' "$YAML_REFS_FILE" || echo "(none)"
      echo "===== END YAML ENTITY REFS ====="
      echo
      echo "===== BEGIN ENTITY XREF (YAML refs not in registry) ====="
      [[ -s "$XREF_REPORT_FILE" ]] && sed -n '1,99999p' "$XREF_REPORT_FILE" || echo "(none)"
      echo "===== END ENTITY XREF ====="
      echo
    } >> "$OUTPUT_FILE"

    # Clean up sidecars if you truly want just one file on disk
    rm -f "$ENTITY_LIST_FILE" "$YAML_REFS_FILE" "$XREF_REPORT_FILE"
  fi
fi

# ---------- optional: git status ----------
if [[ "$INCLUDE_GIT" == "1" && -d "/config/.git" ]]; then
  {
    echo "===== BEGIN GIT STATUS ====="
    ( cd /config && echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'n/a')"
      echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
      echo; git status --porcelain=v1 )
    echo "===== END GIT STATUS ====="
    echo
  } >> "$OUTPUT_FILE"
fi

# ---------- optional: tarball of YAML files ----------
if [[ "$MAKE_TARBALL" == "1" && "$INCLUDE_YAML" == "1" && "${#YAML_FILES[@]}" -gt 0 ]]; then
  TARFILE="$DUMP_DIR/${BASENAME}.tar.gz"
  echo "🗜  Creating tarball: $TARFILE"
  tar -czf "$TARFILE" --transform "s|^/config/||" "${YAML_FILES[@]}"
fi

echo
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - $DATE - v$NEXT_VERSION - $OUTPUT_FILE" >> "$VERSION_TRACKER"
echo "✅ Config dump complete: ${BASENAME}.txt"
