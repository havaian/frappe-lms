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
    echo "❌ Error: .env file not found. Please create one first."
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

# Create necessary directories if they don't exist
echo "📁 Creating necessary directories..."
mkdir -p ./docker/volumes/mariadb-data
mkdir -p ./docker/volumes/redis-data
mkdir -p ./docker/volumes/frappe-sites
mkdir -p ./docker/volumes/frappe-logs

# Set proper permissions for volumes (using current user instead of assuming 1000:1000)
echo "🔐 Setting volume permissions..."
if [ "$EUID" -eq 0 ]; then
    # If running as root, set to frappe user (1000:1000)
    chown -R 1000:1000 ./docker/volumes/frappe-sites
    chown -R 1000:1000 ./docker/volumes/frappe-logs
else
    # If not root, just ensure we can write to these directories
    chmod -R 755 ./docker/volumes/frappe-sites
    chmod -R 755 ./docker/volumes/frappe-logs
fi

# Pull latest images before building
echo "📥 Pulling latest base images..."
$DOCKER_COMPOSE pull

# Build new images without affecting running containers
echo "🏗️  Building new images..."
$DOCKER_COMPOSE build --no-cache

# If builds succeeded, stop and recreate containers
echo "🔄 Swapping to new containers..."
$DOCKER_COMPOSE down

# Start services with dependency order
echo "🚦 Starting database services first..."
$DOCKER_COMPOSE up -d mariadb redis

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
sleep 30

# Check if database is accepting connections
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if $DOCKER_COMPOSE exec mariadb mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} --silent; then
        echo "✅ Database is ready!"
        break
    fi
    echo "⏳ Database not ready yet (attempt $attempt/$max_attempts)..."
    sleep 10
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Database failed to start within expected time"
    exit 1
fi

# Start Frappe application
echo "🌐 Starting Frappe LMS application..."
$DOCKER_COMPOSE up -d frappe

# Wait for Frappe to initialize
echo "⏳ Waiting for Frappe LMS to initialize..."
sleep 60

# Check if Frappe is responding
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -f -s http://localhost:${LMS_PORT:-8000} > /dev/null 2>&1; then
        echo "✅ Frappe LMS is responding!"
        break
    fi
    echo "⏳ Frappe LMS not ready yet (attempt $attempt/$max_attempts)..."
    sleep 15
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "⚠️  Frappe LMS may still be initializing. Check logs with: $DOCKER_COMPOSE logs -f frappe"
fi

# Show container status
echo "📊 Container status:"
$DOCKER_COMPOSE ps

# Show logs for debugging if needed
echo "📝 Recent logs:"
$DOCKER_COMPOSE logs --tail=20

echo ""
echo "🎉 Deployment complete!"
echo "🌐 Access your LMS at: http://localhost:${LMS_PORT:-8000}"
echo "👤 Default login: Administrator / admin"
echo ""
echo "📋 Next steps:"
echo "   1. Change the default admin password"
echo "   2. Configure your site settings"
echo "   3. Set up SSL if deploying to production"
echo ""
echo "🔧 Useful commands:"
echo "   View logs: $DOCKER_COMPOSE logs -f"
echo "   Restart:   $DOCKER_COMPOSE restart"
echo "   Stop:      $DOCKER_COMPOSE down"