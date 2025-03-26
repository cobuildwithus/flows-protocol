#!/usr/bin/env bash

set -e

generate() {
  file=$1
  if [[ $func == "generate" ]]; then
    echo "Creating storage layout diagrams for the following contracts from $contracts_file"
  fi

  echo "=======================" > "$file"
  echo "👁 STORAGE LAYOUT snapshot 👁" >"$file"
  echo "=======================" >> "$file"

  # Read contracts from file, removing @ prefix if present
  contracts_list=$(cat "${contracts_file#@}")
  
  # Log the contracts we're checking
  echo "Checking contracts:"
  echo "$contracts_list"
  echo "..."
  
  for contract in $contracts_list
  do
    { echo -e "\n======================="; echo "➡ $contract" ; echo -e "=======================\n"; } >> "$file"
    FOUNDRY_PROFILE=default forge inspect "$contract" storage-layout >> "$file"
  done
  if [[ $func == "generate" ]]; then
    echo "Storage layout snapshot stored at $file"
  fi
}

if ! command -v forge &> /dev/null
then
    echo "forge could not be found. Please install forge by running:"
    echo "curl -L https://foundry.paradigm.xyz | bash"
    exit
fi

func=$1
contracts_file=$2
filename=.storage-layout
new_filename=.storage-layout.temp

if [[ $func == "check" ]]; then
  generate $new_filename
  if ! cmp -s .storage-layout $new_filename ; then
    echo "storage-layout test: fails ❌"
    echo "The following lines are different:"
    diff -a --suppress-common-lines "$filename" "$new_filename"
    rm $new_filename
    exit 1
  else
    echo "storage-layout test: passes ✅"
    rm $new_filename
    exit 0
  fi
elif [[ $func == "generate" ]]; then
  generate "$filename"
else
  echo "unknown command. Use 'generate' or 'check' as the first argument."
  exit 1
fi
