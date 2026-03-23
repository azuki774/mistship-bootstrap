#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mapfile -t markdown_files < <(git ls-files '*.md' | sort)

status=0

for file in "${markdown_files[@]}"; do
  if grep -q '/home/azuki/work/mistship/' "$file"; then
    echo "Found absolute workspace path in $file" >&2
    status=1
  fi

  mapfile -t links < <(grep -oE '\[[^]]+\]\([^)]+\)' "$file" || true)

  for link in "${links[@]}"; do
    target="${link#*](}"
    target="${target%)}"
    target="${target%%#*}"

    case "$target" in
      ""|http://*|https://*|mailto:*)
        continue
        ;;
      /*)
        echo "Found root or filesystem-style link target in $file: $target" >&2
        status=1
        continue
        ;;
    esac

    resolved="$(dirname "$file")/$target"

    if [[ ! -e "$resolved" ]]; then
      echo "Broken markdown link in $file: $target" >&2
      status=1
    fi
  done
done

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Markdown links look valid."
