#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-yaml-file>"
  exit 1
fi

YAML_FILE=$1

if [ ! -f "$YAML_FILE" ]; then
  echo "❌ Error: File '$YAML_FILE' not found"
  exit 1
fi

# Function to install yq
install_yq() {
  echo "📦 yq not found. Installing yq..."
  
  # Check package managers in order of preference
  if command -v apt-get &>/dev/null; then
    echo "🔧 Installing via apt..."
    sudo apt update
    sudo apt install -y yq
  elif command -v snap &>/dev/null; then
    echo "🔧 Installing via snap..."
    sudo snap install yq
  elif command -v brew &>/dev/null; then
    echo "🔧 Installing via brew..."
    brew install yq
  elif command -v pip3 &>/dev/null; then
    echo "🔧 Installing via pip..."
    pip3 install yq
  elif command -v pip &>/dev/null; then
    echo "🔧 Installing via pip..."
    pip install yq
  else
    echo "❌ Error: Cannot install yq - no supported package manager found"
    echo "💡 Please install yq manually:"
    echo "   Ubuntu/Debian: sudo apt install yq"
    echo "   Snap: sudo snap install yq"
    echo "   macOS: brew install yq"
    echo "   Python: pip install yq"
    exit 1
  fi
  
  # Verify installation
  if command -v yq &>/dev/null; then
    echo "✅ yq installed successfully"
  else
    echo "❌ Error: yq installation failed"
    exit 1
  fi
}

# Check and install yq if needed
if ! command -v yq &>/dev/null; then
  install_yq
fi

# Function to validate the YAML structure
validate_yaml() {
  local file=$1
  
  # Check if yq can parse the file
  if ! yq e 'true' "$file" >/dev/null 2>&1; then
    echo "❌ Error: Invalid YAML format in '$file'"
    return 1
  fi

  # Validate top-level structure
  local required_top_level=("version" "project" "config-env" "services")
  for field in "${required_top_level[@]}"; do
    if ! yq e ".$field" "$file" >/dev/null 2>&1; then
      echo "❌ Error: Missing required top-level field: '$field'"
      return 1
    fi
  done

  # Validate version
  local version=$(yq e '.version' "$file")
  if [ "$version" != "1" ]; then
    echo "❌ Error: Invalid version '$version'. Expected: '1'"
    return 1
  fi

  # Validate config-env path exists
  local config_env=$(yq e '.config-env' "$file")
  if [ ! -f "$config_env" ]; then
    echo "❌ Error: config-env file '$config_env' does not exist"
    return 1
  fi

  # Validate services array
  local services_count=$(yq e '.services | length' "$file")
  if [ "$services_count" -eq 0 ]; then
    echo "❌ Error: No services defined"
    return 1
  fi

  # Validate each service
  for ((i=0; i<services_count; i++)); do
    echo "🔍 Validating service $((i+1))..."
    
    # Required service fields
    local required_service_fields=("name" "description" "domain" "image-name" "version" "env-file")
    for field in "${required_service_fields[@]}"; do
      local value=$(yq e ".services[$i].$field" "$file")
      if [ "$value" == "null" ] || [ -z "$value" ]; then
        echo "❌ Error: Service $((i+1)) missing required field: '$field'"
        return 1
      fi
    done

    # Validate service-specific values
    local service_name=$(yq e ".services[$i].name" "$file")
    local env_file=$(yq e ".services[$i].env-file" "$file")
    local health_path=$(yq e ".services[$i].health-path" "$file")
    local domain=$(yq e ".services[$i].domain" "$file")

    # Validate env-file exists
    if [ ! -f "$env_file" ]; then
      echo "❌ Error: Service '$service_name': env-file '$env_file' does not exist"
      return 1
    fi

    # Validate health-path (optional but if present should start with /)
    if [ "$health_path" != "null" ] && [ -n "$health_path" ]; then
      if [[ ! "$health_path" =~ ^/ ]]; then
        echo "❌ Error: Service '$service_name': health-path '$health_path' must start with /"
        return 1
      fi
    else
      # Set default health-path if not provided
      yq e ".services[$i].health-path = \"/health\"" -i "$file"
      echo "⚠️  Service '$service_name': health-path not specified, defaulting to '/health'"
    fi

    # Validate domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "❌ Error: Service '$service_name': invalid domain format '$domain'"
      return 1
    fi

    # Validate image-name format (should contain at least one /)
    local image_name=$(yq e ".services[$i].image-name" "$file")
    if [[ ! "$image_name" =~ / ]]; then
      echo "❌ Error: Service '$service_name': image-name should be in format 'registry/path'"
      return 1
    fi

    # Validate version format (YYYY.MM.DD.NNNNNN pattern)
    local version=$(yq e ".services[$i].version" "$file")
    if [[ ! "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]]; then
      echo "❌ Error: Service '$service_name': version should be in format 'YYYY.MM.DD.NNNNNN'"
      return 1
    fi
  done

  return 0
}

# Function to display the validated structure
display_structure() {
  local file=$1
  
  echo "✅ YAML structure is valid!"
  echo ""
  echo "📋 Project Overview:"
  echo "   Version: $(yq e '.version' "$file")"
  echo "   Project: $(yq e '.project' "$file")"
  echo "   Config Env: $(yq e '.config-env' "$file")"
  echo ""
  echo "🚀 Services:"
  
  local services_count=$(yq e '.services | length' "$file")
  for ((i=0; i<services_count; i++)); do
    echo "   Service $((i+1)):"
    echo "     Name: $(yq e ".services[$i].name" "$file")"
    echo "     Description: $(yq e ".services[$i].description" "$file")"
    echo "     Domain: $(yq e ".services[$i].domain" "$file")"
    echo "     Image: $(yq e ".services[$i].image-name" "$file"):$(yq e ".services[$i].version" "$file")"
    echo "     Env File: $(yq e ".services[$i].env-file" "$file")"
    echo "     Health Path: $(yq e ".services[$i].health-path" "$file")"
    echo ""
  done
}

# Main validation
echo "🔍 Validating YAML structure of '$YAML_FILE'..."
if validate_yaml "$YAML_FILE"; then
  display_structure "$YAML_FILE"
  echo "🎉 Validation successful! The YAML file follows the required structure."
  exit 0
else
  echo "❌ Validation failed! Please fix the errors above."
  exit 1
fi