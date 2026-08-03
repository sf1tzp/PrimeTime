#!/usr/bin/env bash
# Process raw captures (captures/raw/) into distributable renditions in
# captures/out/, per the outputs table in captures/shots.yaml. Idempotent —
# every present raw file is (re)processed; missing ones are listed and
# skipped so partial re-capture batches work.
#
# Deps: brew install yq jq ffmpeg webp
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTS="$ROOT/captures/shots.yaml"
RAW="$ROOT/captures/raw"
OUT="$ROOT/captures/out"

for tool in yq jq ffmpeg cwebp; do
    command -v "$tool" >/dev/null \
        || { echo "error: '$tool' not found (brew install yq jq ffmpeg webp)" >&2; exit 1; }
done
[[ -d "$RAW" ]] || { echo "error: $RAW does not exist — capture first (/capture skill)" >&2; exit 1; }
mkdir -p "$OUT"

# One line per output: id<TAB>kind<TAB>path<TAB>format<TAB>width<TAB>fps
outputs() {
    yq -o=json '.' "$SHOTS" | jq -r '
        .shots[] | . as $s | .outputs[] |
        [$s.id, $s.kind, .path, .format, (.width // ""), (.fps // "")] | @tsv'
}

missing=()
while IFS=$'\t' read -r id kind path format width fps; do
    ext=png; [[ "$kind" == recording ]] && ext=mov
    raw="$RAW/$id.$ext"
    if [[ ! -f "$raw" ]]; then
        missing+=("$id.$ext")
        continue
    fi
    dst="$OUT/$(basename "$path")"
    case "$format" in
        png)
            cp "$raw" "$dst" ;;
        webp)
            cwebp -quiet -q 90 -metadata none "$raw" -o "$dst" ;;
        gif)
            # Two-pass palette for legible UI text at GIF's 256 colors.
            # -nostdin: ffmpeg must not eat the while-loop's input stream.
            ffmpeg -nostdin -v error -y -i "$raw" \
                -vf "fps=${fps:-12},scale=${width:?gif needs width}:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" \
                "$dst" ;;
        mp4)
            # -2: keep height even for yuv420p; -an: captures carry no audio.
            ffmpeg -nostdin -v error -y -i "$raw" \
                -vf "scale=${width:?mp4 needs width}:-2:flags=lanczos" \
                -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p \
                -movflags +faststart -an "$dst" ;;
        *)  echo "error: unknown format '$format' for shot '$id'" >&2; exit 1 ;;
    esac
    echo "  $id → $(basename "$dst")"
done < <(outputs)

if (( ${#missing[@]} )); then
    printf 'skipped (no raw capture): %s\n' "$(printf '%s ' "${missing[@]}" | tr ' ' '\n' | sort -u | paste -sd' ' -)" >&2
fi
echo "==> renditions in $OUT"
