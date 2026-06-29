#!/bin/bash

# Database and user details
DB_NAME=$1
DB_USER=$2
DB_PWD=$3  # Storing passwords in scripts is not secure for production; consider using environment variables.

# Function to check if database exists
check_db_exists() {
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$1"; then
        echo "Database $1 already exists."
        return 0
    else
        echo "Database $1 does not exist."
        return 1
    fi
}

# Function to check if user exists
check_user_exists() {
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'" | grep -q 1; then
        echo "User $1 already exists."
        return 0
    else
        echo "User $1 does not exist."
        return 1
    fi
}

# Function to create database
create_db() {
    echo "Creating database $1..."
    sudo -u postgres psql -c "CREATE DATABASE $1;"
    if [ $? -eq 0 ]; then
        echo "Database $1 created successfully."
    else
        echo "Failed to create database $1."
        exit 1
    fi
}

# Function to create superuser
create_superuser() {
    echo "Creating superuser $1..."
    sudo -u postgres psql -c "CREATE USER $1 WITH PASSWORD '$2' SUPERUSER;"
    if [ $? -eq 0 ]; then
        echo "Superuser $1 created successfully."
    else
        echo "Failed to create superuser $1."
        exit 1
    fi
}

# Function to create superuser
create_queryuser() {
    echo "Creating query user $1..."
    sudo -u postgres psql -c "CREATE USER $1 WITH PASSWORD '$2' SUPERUSER;"
    if [ $? -eq 0 ]; then
        echo "Query user $1 created successfully."
    else
        echo "Failed to create query user $1."
        exit 1
    fi
}

# Main execution
echo "Checking and setting up PostgreSQL database and superuser..."

# Check and create database if not exists
if ! check_db_exists "${DB_NAME}"; then
    create_db "${DB_NAME}"
fi

# Check and create superuser if not exists
if ! check_user_exists "${DB_USER}"; then
    create_superuser "${DB_USER}" "$DB_PWD"
fi

# Check and create superuser if not exists
if ! check_user_exists "${DB_USER}_query"; then
    create_queryuser "${DB_USER}_query" "$DB_PWD"
fi

echo "PostgreSQL setup completed."