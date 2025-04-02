#!/usr/bin/env bash

set -e

# --- Configuration ---
LAYOUT_FILENAME=".storage-layout.json"
TEMP_FILENAME="$(mktemp .storage-layout.XXXXXX.json)"
CONTRACTS_FILE_ARG=$2
# ---

# --- Helper Functions ---
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Required command '$1' not found."
    if [[ "$1" == "jq" ]]; then
      echo "Please install jq (e.g., 'sudo apt-get install jq', 'brew install jq')."
    elif [[ "$1" == "forge" ]]; then
      echo "Please install forge by running: curl -L https://foundry.paradigm.xyz | bash"
    fi
    exit 1
  fi
}

generate_layout() {
  local output_file="$1"
  local contracts_list_file="$2"
  local mode="$3"

  if [[ "$mode" == "generate" ]]; then
    echo "[Generate] Creating JSON storage layouts for contracts in '$contracts_list_file'"
  elif [[ "$mode" == "check" ]]; then
    echo "[Check] Generating temporary storage layouts for comparison from '$contracts_list_file'"
  fi

  local temp_array=()

  while IFS= read -r contract || [[ -n "$contract" ]]; do
    [[ -z "$contract" ]] || [[ "$contract" =~ ^#.* ]] && continue
    echo "Processing contract: $contract ..."
    
    layout_json=$(FOUNDRY_PROFILE=default forge inspect "$contract" storage-layout --json)
    if ! jq -e . >/dev/null <<<"$layout_json"; then
      echo "Error generating layout for $contract"
      exit 1
    fi

    temp_array+=("$(jq -n --arg name "$contract" --argjson layout "$layout_json" '{($name):$layout}')")
  done < "${contracts_list_file#@}"

  jq -s 'add' <<<"${temp_array[@]}" > "$output_file"

  if ! jq -e . "$output_file" > /dev/null; then
    echo "Error: Generated file $output_file is invalid JSON."
    exit 1
  fi

  if [[ "$mode" == "generate" ]]; then
    echo "Storage layout JSON snapshot stored at $output_file"
  fi
}

cleanup() {
  rm -f "$TEMP_FILENAME"
}
trap cleanup EXIT

# --- Main Script Logic ---

check_command "forge"
check_command "jq"

func=$1
contracts_file=$CONTRACTS_FILE_ARG

if [[ -z "$func" ]] || [[ -z "$contracts_file" ]]; then
  echo "Usage: $0 <check|generate> <contracts_file>"
  echo "  <contracts_file>: Path to a file containing newline-separated contract names (e.g., contracts.txt)"
  exit 1
fi

if [[ ! -f "${contracts_file#@}" ]]; then
   echo "Error: Contracts file '${contracts_file#@}' not found."
   exit 1
fi

if [[ $func == "check" ]]; then
  echo "Checking storage layout against $LAYOUT_FILENAME..."
  if [ ! -f "$LAYOUT_FILENAME" ]; then
    echo "Baseline storage layout file ($LAYOUT_FILENAME) not found. Generate it first with:"
    echo "$0 generate $contracts_file"
    exit 1
  fi

  generate_layout "$TEMP_FILENAME" "$contracts_file" "check"

  echo "Comparing current layout ($TEMP_FILENAME) with baseline ($LAYOUT_FILENAME)..."
  if ! diff -u <(jq -S . "$LAYOUT_FILENAME") <(jq -S . "$TEMP_FILENAME"); then
    echo "----------------------------------------"
    echo "storage-layout test (JSON): fails ❌"
    echo "Differences detected. See diff output above."
    echo "Temporary layout saved to $TEMP_FILENAME for inspection."
    exit 1
  else
    echo "----------------------------------------"
    echo "storage-layout test (JSON): passes ✅"
    exit 0
  fi

elif [[ $func == "generate" ]]; then
  generate_layout "$LAYOUT_FILENAME" "$contracts_file" "generate"
else
  echo "Error: Unknown command '$func'. Use 'generate' or 'check'."
  exit 1
fi