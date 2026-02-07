#!/bin/bash
set -e

SDK_DIR="$1"
if [ -z "$SDK_DIR" ]; then
  echo "Usage: patch_wifi_dts.sh <sdk_dir>" >&2
  exit 2
fi

LINUX_DIR="$SDK_DIR/linux_5.10"
if [ ! -d "$LINUX_DIR" ]; then
  echo "Linux tree not found at $LINUX_DIR"
  exit 0
fi

PROPS=(
  'status = "okay";'
  'bus-width = <4>;'
  'non-removable;'
  'keep-power-in-suspend;'
)

if [ -n "${WIFI_DTS_PROPS:-}" ]; then
  IFS=';' read -r -a EXTRA <<< "${WIFI_DTS_PROPS}"
  for p in "${EXTRA[@]}"; do
    p="$(echo "$p" | xargs)"
    if [ -n "$p" ]; then
      [[ "$p" == *";" ]] || p="${p};"
      PROPS+=("$p")
    fi
  done
fi

patched=0

while IFS= read -r -d '' dts; do
  if ! grep -q -E '4320000|wifi-sd|sdhci@4320000' "$dts"; then
    continue
  fi

  tmp="${dts}.tmp"
  awk -v props="$(printf '%s\n' "${PROPS[@]}")" '
    function has_prop(block, key) {
      return block ~ "^[[:space:]]*" key "([[:space:]]|;|=)"
    }
    BEGIN {
      in_node=0
      depth=0
      node_block=""
      split(props, prop_lines, "\n")
    }
    /^[[:space:]]*[^/[:space:]].*@4320000[[:space:]]*\{/ {
      in_node=1
      depth=1
      node_block=""
      print
      # Insert props immediately after the opening brace
      for (i in prop_lines) {
        line = prop_lines[i]
        if (length(line) == 0) continue
        print "    " line
      }
      next
    }
    {
      if (in_node) {
        node_block = node_block $0 "\n"
        # Track braces to know when node ends
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          else if (c == "}") depth--
        }
        if (depth == 0) {
          in_node=0
        }
      }
      print
    }
  ' "$dts" > "$tmp"

  if ! cmp -s "$dts" "$tmp"; then
    mv "$tmp" "$dts"
    echo "Patched Wi-Fi SDIO node in: $dts"
    patched=1
  else
    rm -f "$tmp"
  fi
done < <(find "$LINUX_DIR/arch" -type f -name "*.dts" -print0)

if [ "$patched" -eq 0 ]; then
  echo "No Wi-Fi SDIO node patched (node not found or already configured)."
fi
