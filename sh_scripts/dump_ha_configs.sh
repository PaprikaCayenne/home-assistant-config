#!/bin/bash

# ================================================
# Script: dump_ha_configs.sh
# Location: /config/sh_scripts/
# Version: v1.2.0 — Auto-Versioned Home Assistant Config Dump
# Description: Creates daily versioned snapshots of all .yaml/.yml config files.
#              Archives previous versions, tracks versions, and shows progress.
# ================================================

DATE=$(date +%m_%d_%Y)
DUMP_DIR="/config/sh_scripts"
OLD_DIR="$DUMP_DIR/_old"
VERSION_TRACKER="$DUMP_DIR/ha_config_versions.log"

mkdir -p "$DUMP_DIR"
mkdir -p "$OLD_DIR"

# Determine version for today
LAST_VERSION=$(grep "$DATE" "$VERSION_TRACKER" 2>/dev/null | tail -n 1 | sed -E 's/.*_v([0-9]+)\.txt/\1/')
if [[ -z "$LAST_VERSION" ]]; then
  NEXT_VERSION=1
else
  NEXT_VERSION=$((LAST_VERSION + 1))
fi

OUTPUT_FILE="$DUMP_DIR/ha_config_dump-${DATE}_v${NEXT_VERSION}.txt"

echo "🛠 Archiving previous config dumps..."
find "$DUMP_DIR" -maxdepth 1 -name 'ha_config_dump-*.txt' -exec mv {} "$OLD_DIR/" \;

# Optional cleanup (keep last 20)
ls -t "$OLD_DIR"/ha_config_dump-*.txt 2>/dev/null | tail -n +21 | xargs -r rm

echo "📦 Creating config snapshot: $OUTPUT_FILE"
> "$OUTPUT_FILE"

# File discovery
FILES=($(find /config -type f \( -iname "*.yaml" -o -iname "*.yml" \) | sort))
TOTAL=${#FILES[@]}
CURRENT=0

progress_bar() {
  local progress=$((CURRENT * 100 / TOTAL))
  local bar_width=40
  local filled=$((progress * bar_width / 100))
  local empty=$((bar_width - filled))
  local bar=$(printf "%${filled}s" | tr ' ' '#')
  bar+=$(printf "%${empty}s")
  echo -ne "\r🔄 Progress: [${bar}] ${progress}%"
}

for file in "${FILES[@]}"; do
  echo -e "\n==================================================" >> "$OUTPUT_FILE"
  echo -e "📄 File: $file" >> "$OUTPUT_FILE"
  echo -e "==================================================\n" >> "$OUTPUT_FILE"
  cat "$file" >> "$OUTPUT_FILE" 2>/dev/null
  echo -e "\n\n" >> "$OUTPUT_FILE"
  ((CURRENT++))
  progress_bar
done

echo
echo "$DATE - v$NEXT_VERSION - $OUTPUT_FILE" >> "$VERSION_TRACKER"
echo "✅ Config dump complete: ha_config_dump-${DATE}_v${NEXT_VERSION}.txt"
