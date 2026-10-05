#!/bin/bash

# Configuration
CONTAINER_NAME="frappe_docker-backend-1"
APP_NAME="forging_erp"
REPO_URL="https://github.com/dkalola/forging_erp.git"

echo "=========================================="
echo "Starting backup for custom app: $APP_NAME"
echo "=========================================="

# Step 1: Copy app from Docker container
echo "-> Copying app from Docker container ($CONTAINER_NAME)..."
docker cp "$CONTAINER_NAME:/home/frappe/frappe-bench/apps/$APP_NAME" .

if [ ! -d "$APP_NAME" ]; then
    echo "❌ Error: Failed to copy app from container. Check if the app name is correct."
    exit 1
fi

# Step 2: Navigate into the app directory
cd "$APP_NAME" || exit

# Step 3: Initialize Git and Link Remote
echo "-> Setting up Git repository..."
if [ ! -d ".git" ]; then
    git init
    git branch -M main
fi

git remote remove origin 2>/dev/null
git remote add origin "$REPO_URL"

echo "-> Adding and committing files..."
git add .
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git commit -m "Automated backup: $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo "No changes to commit."
fi

echo "-> Pulling latest changes from remote..."
git pull origin main --rebase --allow-unrelated-histories || echo "Pull skipped or not needed."

echo "-> Pushing to GitHub..."
git push -u origin main

echo "=========================================="
echo "✅ Backup completed successfully!"
echo "=========================================="