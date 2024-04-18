#!/bin/sh

set -e

while [ $# -gt 0 ]; do
  case "$1" in
    --airnity-ca)
      AIRNITY_CA=true
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

packages_to_install=""

if [ "$AIRNITY_CA" = true ] && ! command -v curl > /dev/null; then
  packages_to_install="$packages_to_install curl"
fi

if [ "$AIRNITY_CA" = true ] && ! command -v update-ca-certificates > /dev/null; then
  packages_to_install="$packages_to_install ca-certificates"
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    alpine)
      apk add --no-cache $packages_to_install
      ;;
    debian|ubuntu)
      apt-get update
      apt-get install -y $packages_to_install
      ;;
    centos|fedora)
      yum install -y $packages_to_install
      ;;
    *)
      echo "Unsupported OS: $ID"
      exit 1
      ;;
  esac
else
  echo "Unknown OS"
  exit 1
fi


if [ "$AIRNITY_CA" = true ]; then
  curl -s -o /usr/local/share/ca-certificates/ca_bundle.crt https://raw.githubusercontent.com/airnity/public/main/ca_bundle.crt
  update-ca-certificates
fi
