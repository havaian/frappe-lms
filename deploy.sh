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

# Skip permission setting - Docker will handle volume permissions automatically
echo "🔧 Docker will handle volume permissions automatically"

# Pull latest images before building
echo "📥 Pulling latest base images..."
$DOCKER_COMPOSE pull || echo "⚠️  Pull failed, continuing with local images"

# Build new images without affecting running containers
echo "🏗️  Building new images..."
$DOCKER_COMPOSE build --no-cache || echo "⚠️  Build failed, using existing images"

# If builds succeeded, stop and recreate containers
echo "🔄 Swapping to new containers..."
$DOCKER_COMPOSE down || echo "ℹ️  No containers to stop"

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
    if $DOCKER_COMPOSE exec mariadb mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; then
        echo "✅ Database is ready!"
        break
    fi
    echo "⏳ Database not ready yet (attempt $attempt/$max_attempts)..."
    sleep 10
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Database failed to start within expected time"
    echo "🔍 Database logs:"
    $DOCKER_COMPOSE logs mariadb --tail=10
    exit 1
fi

# Start Frappe application
echo "🌐 Starting Frappe LMS application..."
$DOCKER_COMPOSE up -d frappe

# Wait for Frappe to initialize
echo "⏳ Waiting for Frappe LMS to initialize..."
sleep 60

# Check if Frappe is responding (with better error handling)
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -f -s --connect-timeout 5 --max-time 10 http://localhost:${LMS_PORT:-8000} > /dev/null 2>&1; then
        echo "✅ Frappe LMS is responding!"
        break
    fi
    echo "⏳ Frappe LMS not ready yet (attempt $attempt/$max_attempts)..."
    sleep 15
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "⚠️  Frappe LMS may still be initializing. Check logs with: $DOCKER_COMPOSE logs -f frappe"
    echo "🔍 Recent Frappe logs:"
    $DOCKER_COMPOSE logs frappe --tail=20
fi

# Show container status
echo "📊 Container status:"
$DOCKER_COMPOSE ps

# Show logs for debugging if needed (but limit output)
echo "📝 Recent logs (last 10 lines per service):"
$DOCKER_COMPOSE logs --tail=10

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
echo "   Debug:     $DOCKER_COMPOSE exec frappe bash"