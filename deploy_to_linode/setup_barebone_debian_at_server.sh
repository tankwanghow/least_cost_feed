#!/bin/bash

# Function to check if a command is installed
check_command_version() {
  local cmd=$1
  if command -v $cmd &>/dev/null; then
    echo "$cmd is installed. Version: $("$cmd" --version | head -n 1)"
    return 0
  else
    echo "$cmd is not installed."
    return 1
  fi
}

# Function to check if a command is installed
check_command_v() {
  local cmd=$1
  if command -v $cmd &>/dev/null; then
    echo "$cmd is installed. Version: $("$cmd" -v | head -n 1)"
    return 0
  else
    echo "$cmd is not installed."
    return 1
  fi
}

# Function to install Docker
install_docker() {
  echo "Installing Docker..."

  sudo apt-get update

  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

  sudo curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  if check_command docker; then
    echo "Docker installed successfully."
    return 0
  else
    echo "Failed to install Docker."
    return 1
  fi
}

# Function to install Nginx
install_nginx() {
  echo "Installing Nginx..."

  sudo apt-get install -y nginx

  if check_command nginx; then
    echo "Nginx installed successfully."
    return 0
  else
    echo "Failed to install Nginx."
    return 1
  fi
}

# Function to install PostgreSQL 17
install_postgres17() {
  echo "Installing PostgreSQL 17..."

  # Add PostgreSQL repository for latest version
  echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list
  sudo wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

  sudo apt-get update

  # Install PostgreSQL 17
  sudo apt-get install -y postgresql-17 postgresql-client-17

  # Check if PostgreSQL was installed
  if check_command psql; then
    echo "PostgreSQL 17 installed successfully."
    return 0
  else
    echo "Failed to install PostgreSQL 17."
    return 1
  fi
}

# Main script flow
# Check and install Docker
if ! check_command_version docker; then
  install_docker
fi

# Check and install Nginx
if ! check_command_v nginx; then
  install_nginx
fi

# Check and install PostgreSQL 17
if ! check_command_version psql; then
  install_postgres17
else
  # Check if installed version is 17, if not, proceed with installation of 17
  installed_version=$(psql --version | awk '{print $3}' | cut -d'.' -f1)
  if [ "$installed_version" != "17" ]; then
    echo "PostgreSQL version is not 17. Installing PostgreSQL 17."
    install_postgres17
  else
    echo "PostgreSQL 17 is already installed."
  fi
fi
