#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# optimize_images.sh
#
# Build-time / local helper that:
#   1. Converts JPG/PNG files to WebP (quality 80) when a .webp sibling
#      does not already exist (or is older than the source).
#   2. Generates common responsive width variants (400w, 800w) for images
#      that are wide enough.
#
# Safe to run repeatedly (idempotent). Intended to be called from CI before
# the Jekyll build and also locally when you add new images.
#
# Usage:
#   ./_scripts/optimize_images.sh
# ---------------------------------------------------------------------------

set -euo pipefail

QUALITY="${WEBP_QUALITY:-80}"
DIRS=("images" "_notebooks/my_icons")

# Widths at which we generate extra variants (only if source is larger)
VARIANT_WIDTHS=(400 800)

log()  { printf '→ %s\n' "$*"; }
skip() { printf '  skip: %s\n' "$*"; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    echo "Install with: sudo apt-get install -y webp   (or brew install webp)" >&2
    exit 1
  fi
}

need_cmd cwebp
need_cmd identify   # from ImageMagick – used for dimensions

convert_to_webp() {
  local src="$1"
  local dest="${src%.*}.webp"

  # Skip if webp already exists and is newer than source
  if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
    skip "$(basename "$dest") already up-to-date"
    return 0
  fi

  log "Converting $(basename "$src") → $(basename "$dest")"
  cwebp -quiet -q "$QUALITY" "$src" -o "$dest"
}

make_variant() {
  local src="$1"   # preferably a .webp we just created / already have
  local width="$2"
  local base="${src%.*}"
  local dest="${base}-${width}.webp"

  # Only create if source is wider than the target
  local src_w
  src_w=$(identify -format '%w' "$src" 2>/dev/null || echo 0)
  if (( src_w <= width )); then
    return 0
  fi

  if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
    skip "$(basename "$dest") already up-to-date"
    return 0
  fi

  log "Generating ${width}w variant → $(basename "$dest")"
  cwebp -quiet -q "$QUALITY" -resize "$width" 0 "$src" -o "$dest"
}

process_file() {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}"   # lowercase

  case "$ext" in
    jpg|jpeg|png)
      convert_to_webp "$file"
      local webp="${file%.*}.webp"
      if [[ -f "$webp" ]]; then
        for w in "${VARIANT_WIDTHS[@]}"; do
          make_variant "$webp" "$w"
        done
      fi
      ;;
    webp)
      # Already webp – still generate missing width variants
      for w in "${VARIANT_WIDTHS[@]}"; do
        make_variant "$file" "$w"
      done
      ;;
    *)
      # gif, svg, ico, pdf, etc. – leave alone
      ;;
  esac
}

main() {
  log "Image optimization starting (quality=${QUALITY})"
  local count=0

  for dir in "${DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
      skip "directory $dir does not exist"
      continue
    fi
    log "Scanning $dir/"
    # Use find so we handle spaces safely; limit depth to avoid surprises
    while IFS= read -r -d '' file; do
      process_file "$file"
      ((count++)) || true
    done < <(find "$dir" -maxdepth 2 -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
      \) -print0)
  done

  log "Finished. Processed ${count} candidate file(s)."
}

main "$@"
