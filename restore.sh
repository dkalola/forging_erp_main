#!/bin/bash

# Configuration
CONTAINER_NAME="frappe_docker-backend-1"
APP_NAME="forging_erp"
REPO_URL="https://github.com/dkalola/forging_erp.git"
SITE_NAME="frontend"  # Your ERPNext site name
DB_PASSWORD="admin"   # Default database password

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dynamically locate or clone the frappe_docker directory
if [ -d "$SCRIPT_DIR/../frappe_docker" ]; then
    DOCKER_DIR="$SCRIPT_DIR/../frappe_docker"
elif [ -d "$SCRIPT_DIR/frappe_docker" ]; then
    DOCKER_DIR="$SCRIPT_DIR/frappe_docker"
else
    echo "⚠️ 'frappe_docker' directory not found. Cloning it..."
    cd "$SCRIPT_DIR" || exit 1
    git clone https://github.com/frappe/frappe_docker.git
    DOCKER_DIR="$SCRIPT_DIR/frappe_docker"
fi

echo "=========================================="
echo "Starting ERPNext & Custom App Restoration"
echo "=========================================="

# Step 1: Navigate to Docker directory and ensure containers are running
if [ ! "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo "⚠️ Containers are not running. Starting Docker Compose..."
    cd "$DOCKER_DIR" || exit 1

    if [ -f "compose.yaml" ] || [ -f "docker-compose.yml" ]; then
        docker-compose up -d
    else
        echo "❌ Error: Docker compose file not found in $DOCKER_DIR."
        exit 1
    fi
    echo "-> Waiting for containers to initialize..."
    sleep 10
else
    # Make sure we are in the docker directory for later compose commands
    cd "$DOCKER_DIR" || exit 1
fi

# Step 2: Check if the ERPNext site is initialized
echo "-> Checking if site '$SITE_NAME' exists..."
SITE_EXISTS=$(docker exec -it "$CONTAINER_NAME" bash -c "test -f /home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json && echo 'yes' || echo 'no'")
SITE_EXISTS=$(echo "$SITE_EXISTS" | tr -d '\r')

if [ "$SITE_EXISTS" != "yes" ]; then
    echo "⚠️ Site '$SITE_NAME' not found. Initializing fresh site..."
    
    # Give database a moment to be completely healthy
    sleep 5

    docker exec -it "$CONTAINER_NAME" bench new-site "$SITE_NAME" \
        --admin-password "$DB_PASSWORD" \
        --db-root-password "$DB_PASSWORD" \
        --no-mariadb-socket
    
    echo "✅ Fresh site '$SITE_NAME' initialized!"
else
    echo "✔ Site '$SITE_NAME' already exists."
fi

# Step 3: Clone or Update your custom app inside the container
echo "-> Cloning custom app ($APP_NAME) from GitHub..."
docker exec -it "$CONTAINER_NAME" bash -c "
    cd /home/frappe/frappe-bench/apps
    if [ -d '$APP_NAME' ]; then
        echo 'App folder already exists. Pulling latest code...'
        cd '$APP_NAME' && git pull origin main
    else
        git clone '$REPO_URL'
    fi
"

# Step 4: Install your custom app on the site
echo "-> Installing app on site: $SITE_NAME..."
docker exec -it "$CONTAINER_NAME" bench --site "$SITE_NAME" install-app "$APP_NAME" 2>/dev/null || echo "App already installed, skipping installation step."

# Step 5: Run Migrations & Build Assets
echo "-> Running database migrations..."
docker exec -it "$CONTAINER_NAME" bench --site "$SITE_NAME" migrate

echo "-> Building frontend assets..."
docker exec -it "$CONTAINER_NAME" bench build

# Step 6: Restart containers to refresh background queues and web workers
echo "-> Restarting containers to apply changes..."
cd "$DOCKER_DIR" && docker-compose down
cd "$DOCKER_DIR" && docker-compose up -d

echo "=========================================="
echo "✅ Everything restored and running successfully!"
echo "=========================================="