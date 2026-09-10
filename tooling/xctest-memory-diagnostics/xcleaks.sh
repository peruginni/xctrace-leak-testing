#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

usage() {
  echo "Usage: xcleaks.sh <result.xcresult> <attachments-directory>" >&2
}

export_attachments() {
  local result_bundle="$1"
  local attachments_dir="$2"

  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachments_dir"
}

extract_memory_graphs() {
  local attachments_dir="$1"
  local memgraphs_dir="$2"
  local archive_count=0
  local archive
  local archive_contents
  local archive_dir

  mkdir -p "$memgraphs_dir"

  while IFS= read -r -d '' archive; do
    if ! archive_contents="$(/usr/bin/tar -tf "$archive" 2>/dev/null)"; then
      continue
    fi

    if ! grep -Eq '/post_.*\.memgraph$' <<<"$archive_contents"; then
      continue
    fi

    archive_count=$((archive_count + 1))
    archive_dir="$memgraphs_dir/$archive_count"
    mkdir -p "$archive_dir"
    /usr/bin/tar -xf "$archive" -C "$archive_dir"
  done < <(find "$attachments_dir" -type f ! -name manifest.json -print0)

  if [[ "$archive_count" -eq 0 ]]; then
    echo "No memory-graph attachment was exported." >&2
    return 2
  fi
}

check_memory_graphs() {
  local memgraphs_dir="$1"
  local graph_count=0
  local found_leaks=0
  local graph
  local output
  local status

  while IFS= read -r -d '' graph; do
    graph_count=$((graph_count + 1))
    output="$memgraphs_dir/post-$graph_count.leaks.txt"

    set +e
    /usr/bin/leaks --quiet --list "$graph" >"$output" 2>&1
    status=$?
    set -e

    grep -E '^Process .* leaks? for|^Leak:' "$output" || true
    echo "leaks output: $output"

    case "$status" in
      0) ;;
      1) found_leaks=1 ;;
      *)
        echo "leaks exited with unexpected status $status." >&2
        return 2
        ;;
    esac
  done < <(find "$memgraphs_dir" -type f -name 'post_*.memgraph' -print0)

  if [[ "$graph_count" -eq 0 ]]; then
    echo "No post-test memory graph was found." >&2
    return 2
  fi

  return "$found_leaks"
}

main() {
  if [[ "$#" -ne 2 ]]; then
    usage
    return 2
  fi

  local result_bundle="$1"
  local attachments_dir="$2"
  local memgraphs_dir="$attachments_dir/memgraphs"

  if [[ ! -f "$result_bundle/Info.plist" ]]; then
    echo "Valid result bundle not found: $result_bundle" >&2
    echo "The test may have been interrupted before Xcode finished writing it." >&2
    return 2
  fi

  if [[ -e "$attachments_dir" ]]; then
    echo "Attachments directory already exists: $attachments_dir" >&2
    return 2
  fi

  export_attachments "$result_bundle" "$attachments_dir"
  extract_memory_graphs "$attachments_dir" "$memgraphs_dir"
  check_memory_graphs "$memgraphs_dir"
}

main "$@"
