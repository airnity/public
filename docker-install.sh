#!/bin/sh

set -e

# Function to run commands with sudo if not root
run_with_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Variable to keep track of packages installed by the script
installed_packages=""

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

package_installed() {
  if command_exists apk; then
    apk info --installed "$1" >/dev/null 2>&1
  elif command_exists dpkg-query; then
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
  else
    echo "Unsupported package manager."
    exit 1
  fi
}

# Function to install a package using apk (Alpine Linux)
install_package_apk() {
  if ! package_installed "$1"; then
    run_with_sudo apk add --no-cache "$1"
    if [ "$2" != "true" ]; then
      echo "Adding $1 to installed packages..."
      installed_packages="${installed_packages} $1"
    fi
  fi
}

# Function to install a package using apt (Debian/Ubuntu)
install_package_apt() {
  if ! package_installed "$1"; then
    run_with_sudo apt-get install -y -qq "$1"
    if [ "$2" != "true" ]; then
      echo "Adding $1 to installed packages..."
      installed_packages="${installed_packages} $1"
    fi
  fi
}

# Function to install a package using the appropriate package manager
install_package() {
  if command_exists apk; then
    install_package_apk "$1" "$2"
  elif command_exists apt-get; then
    install_package_apt "$1" "$2"
  else
    echo "Unsupported package manager."
    exit 1
  fi
}

#Function to download a file
download_file() {
  install_package curl
  curl -sSL "$1" -o "$2"
}

ca_cert_path="/usr/local/share/ca-certificates/ca_bundle.crt"

# Function to install CA certificate
install_ca_certificate() {
  echo "\nInstalling CA certificate..."
  CERT_URL="https://raw.githubusercontent.com/airnity/public/main/ca_bundle.crt"

  download_file "$CERT_URL" "/tmp/ca-certificate.pem"

  install_package ca-certificates
  run_with_sudo cp /tmp/ca-certificate.pem "$ca_cert_path"
  run_with_sudo update-ca-certificates

  rm -f /tmp/ca-certificate.pem

  echo "CA certificate installed successfully.\n"
}

install_gcloud() {
  echo "Installing Google Cloud SDK..."
  install_package curl
  install_package bash
  install_package python3 true

  # Set installation directory
  GCLOUD_DIR="/usr/local/google-cloud-sdk"

  # Download and run the installer with proper arguments
  export CLOUDSDK_INSTALL_DIR="/usr/local"
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1

  curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/usr/local

  # Install additional components
  run_with_sudo "$GCLOUD_DIR/bin/gcloud" components install beta gke-gcloud-auth-plugin --quiet

  # Create symlinks in /usr/local/bin for system-wide access
  run_with_sudo ln -sf "$GCLOUD_DIR/bin/gcloud" /usr/local/bin/gcloud
  run_with_sudo ln -sf "$GCLOUD_DIR/bin/gsutil" /usr/local/bin/gsutil
  run_with_sudo ln -sf "$GCLOUD_DIR/bin/bq" /usr/local/bin/bq

  # Make sure the installation directory has proper permissions
  run_with_sudo chmod -R 755 "$GCLOUD_DIR"

  echo "Google Cloud SDK installed successfully.\n"
}

# Function to add repository authentication keys and URL
configure_elixir_repo() {
  local auth_key="$1"
  local api_key="$2"
  local url="$3"

  if [ -n "$auth_key" ] && [ -n "$api_key" ] && [ -n "$url" ]; then
    if ! command_exists mix; then
      echo "Error: 'mix' command not found. Make sure Elixir is installed."
      exit 1
    fi

    echo "Configuring Elixir repository..."
    mkdir -p ~/.airnity/

    echo "$api_key" > ~/.airnity/elixir_repo_api_key

    download_file "https://raw.githubusercontent.com/airnity/public/main/elixir_repo_rsa_public.pem" "/tmp/elixir_repo_rsa_public.pem"

    mix local.hex --force && mix local.rebar --force

    mix hex.repo add airnity "$url" --public-key /tmp/elixir_repo_rsa_public.pem --auth-key "$auth_key"

    mix hex.config cacerts_path "$ca_cert_path"

    echo "Elixir repository configured successfully.\n"
  else
    echo "Error: Missing one or more required arguments: --airnity-elixir-repo-auth-key, --airnity-elixir-repo-api-key, --airnity-elixir-repo-url"
    exit 1
  fi
}

# Function to setup Git with GitHub App token
setup_git_with_token() {
  local token="$1"

  if [ -n "$token" ]; then
    echo "Setting up Git with GitHub App token..."

    # Ensure Git is installed
    install_package git

    # Configure Git to use the token
    git config --global url."https://x-access-token:${token}@github.com/".insteadOf "https://github.com/"

    echo "Git configured successfully with GitHub App token.\n"
  else
    echo "Error: GitHub App token is empty."
    exit 1
  fi
}

# Update apt package index
if command_exists apt-get; then
  echo "Updating package index..."
  run_with_sudo apt-get update -qq
fi

# Parse arguments
install_ca_cert=false
install_elixir_repo=false
install_gcloud=false
setup_git=false
airnity_elixir_repo_auth_key=""
airnity_elixir_repo_api_key=""
airnity_elixir_repo_url="https://mini-repo.central.it.airnity.internal/repos/airnity"
gh_ci_token=""

for arg in "$@"; do
  case "$arg" in
    --airnity-ca)
      install_ca_cert=true
      ;;
    --airnity-elixir-repo-auth-key=*)
      install_elixir_repo=true
      install_ca_cert=true
      airnity_elixir_repo_auth_key="${arg#*=}"
      ;;
    --airnity-elixir-repo-api-key=*)
      install_elixir_repo=true
      install_ca_cert=true
      airnity_elixir_repo_api_key="${arg#*=}"
      ;;
    --airnity-elixir-repo-url=*)
      airnity_elixir_repo_url="${arg#*=}"
      ;;
    --gcloud)
      install_gcloud=true
      ;;
    --gh-ci-token=*)
      setup_git=true
      gh_ci_token="${arg#*=}"
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
if $install_elixir_repo; then
  configure_elixir_repo "$airnity_elixir_repo_auth_key" "$airnity_elixir_repo_api_key" "$airnity_elixir_repo_url"
fi

# Install Google Cloud SDK if --gcloud argument is present
if $install_gcloud; then
  install_gcloud
fi

# Setup Git with GitHub App token if --gh-ci-token is set and not empty
if $setup_git; then
  setup_git_with_token "$gh_ci_token"
fi

# Uninstall temporary packages
for pkg in $installed_packages; do
  echo "Removing $pkg..."
  if command_exists apk; then
    run_with_sudo apk del "$pkg"
  elif command_exists apt-get; then
    run_with_sudo apt-get purge -y -qq "$pkg"
    run_with_sudo apt-get autoremove -y -qq
  fi
done

echo "Script executed successfully."
