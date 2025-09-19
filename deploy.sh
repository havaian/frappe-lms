#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting Frappe LMS deployment process..."

# Function to check if docker compose command exists and use appropriate version
check_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose -f ./docker/docker-compose.yml"
    else
        echo "docker compose -f ./docker/docker-compose.yml"
    fi
}

DOCKER_COMPOSE=$(check_docker_compose)

# Check if .env file exists
if [ ! -f ./docker/.env ]; then
    echo "❌ Error: .env file not found in ./docker/"
    echo "💡 Copy .env.example to .env and configure your settings."
    exit 1
fi

# Source environment variables for validation
source ./docker/.env

# Validate required environment variables
required_vars=("FRAPPE_SITE_NAME_HEADER" "DB_PASSWORD" "MYSQL_ROOT_PASSWORD")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: Required environment variable $var is not set in .env"
        exit 1
    fi
done

# Make init.sh executable
echo "🔧 Making init.sh executable..."
chmod +x ./docker/init.sh

# Pull latest images
echo "📥 Pulling latest base images..."
$DOCKER_COMPOSE pull || echo "⚠️  Pull failed, continuing with local images"

# Stop existing containers
echo "🔄 Stopping existing containers..."
$DOCKER_COMPOSE down || echo "ℹ️  No containers to stop"

# Start all services
echo "🚦 Starting all services..."
$DOCKER_COMPOSE up -d --build

# Wait for services to be ready
    echo "✅ Derployment completed!"