#!/bin/sh

# Variable to keep track of packages installed by the script
installed_packages=""

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install a package using apk (Alpine Linux)
install_package_apk() {
  if ! command_exists "$1"; then
    apk add --no-cache "$1"
    installed_packages="${installed_packages} $1"
  fi
}

# Function to install a package using apt (Debian/Ubuntu)
install_package_apt() {
  if ! command_exists "$1"; then
    apt-get install -y -qq "$1"
    installed_packages="${installed_packages} $1"
  fi
}

# Function to install a package using the appropriate package manager
install_package() {
  if command_exists apk; then
    install_package_apk "$1"
  elif command_exists apt-get; then
    install_package_apt "$1"
  else
    echo "Unsupported package manager."
    exit 1
  fi
}

# Function to download a file
download_file() {
  install_package wget
  wget -qO "$2" "$1"
}

# Function to install CA certificate
install_ca_certificate() {
  echo "Installing CA certificate..."
  # URL of the CA certificate file
  CERT_URL="https://raw.githubusercontent.com/airnity/public/main/ca_bundle.crt"

  # Download the certificate
  download_file "$CERT_URL" "/tmp/ca-certificate.pem"

  # Install the CA certificate using the appropriate package manager
  install_package ca-certificates
  cp /tmp/ca-certificate.pem /usr/local/share/ca-certificates/ca-certificate.crt
  update-ca-certificates

  # Remove the downloaded certificate file
  rm -f /tmp/ca-certificate.pem

  echo "CA certificate installed successfully."
}

# Function to add repository authentication keys and URL
configure_elixir_repo() {
  # Extract repository configuration from command-line arguments
  local auth_key="$1"
  local api_key="$2"
  local url="$3"

  if [ -n "$auth_key" ] && [ -n "$api_key" ] && [ -n "$url" ]; then
    if ! command_exists mix; then
      echo "Error: 'mix' command not found. Make sure Elixir is installed."
      exit 1
    fi

    echo "Configuring Elixir repository..."
    # Create directory for configuration
    mkdir -p ~/.airnity/

    # Save API key to a file
    echo "$api_key" >> ~/.airnity/elixir_repo_api_key

    # Download public key file
    download_file "https://raw.githubusercontent.com/airnity/public/main/elixir_repo_rsa_public.pem" "/tmp/elixir_repo_rsa_public.pem"


    mix local.hex --force && mix local.rebar --force

    # Add Elixir repository with authentication keys and URL
    mix hex.repo add airnity "$url" --public-key /tmp/elixir_repo_rsa_public.pem --auth-key "$auth_key"

    # Set CA certificates path
    mix hex.config cacerts_path /usr/local/share/ca-certificates/ca_bundle.crt

    echo "Elixir repository configured successfully."
  else
    echo "Error: Missing one or more required arguments: --airnity-elixir-repo-auth-key, --airnity-elixir-repo-api-key, --airnity-elixir-repo-url"
    exit 1
  fi
}

# Update apt package index
if command_exists apt-get; then
  echo "Updating package index..."
  apt-get update -qq
fi

# Install wget if not already installed
if ! command_exists wget; then
  install_package wget
fi

# Parse arguments
install_ca_cert=false
airnity_auth_key=""
airnity_api_key=""
airnity_repo_url=""
for arg in "$@"; do
  case "$arg" in
    --airnity-ca)
      install_ca_cert=true
      ;;
    --airnity-elixir-repo-auth-key=*)
      airnity_auth_key="${arg#*=}"
      ;;
    --airnity-elixir-repo-api-key=*)
      airnity_api_key="${arg#*=}"
      ;;
    --airnity-elixir-repo-url=*)
      airnity_repo_url="${arg#*=}"
      ;;
    *)
      ;;
  esac
done

# Install CA certificate if --airnity-ca argument is present
if $install_ca_cert; then
  install_ca_certificate
fi

# Configure Elixir repository if necessary arguments are provided
if [ -n "$airnity_auth_key" ] && [ -n "$airnity_api_key" ] && [ -n "$airnity_repo_url" ]; then
  configure_elixir_repo "$airnity_auth_key" "$airnity_api_key" "$airnity_repo_url"
fi

# Uninstall temporary packages
for pkg in $installed_packages; do
  echo "Removing $pkg..."
  if command_exists apk; then
    apk del "$pkg"
  elif command_exists apt-get; then
    apt-get purge -y -qq "$pkg"
    apt-get autoremove -y -qq
  fi
done

echo "Script executed successfully."
