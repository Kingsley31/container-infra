#!/bin/bash

# Check if a file was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <env-file>"
  exit 1
fi

ENV_FILE="$1"

# Check if the file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: File '$ENV_FILE' not found."
  exit 1
fi

# Read the env file, ignore comments and empty lines, and print variables space-separated
tr '\n' ' ' < <(grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$')

# Add a newline at the end
echo
