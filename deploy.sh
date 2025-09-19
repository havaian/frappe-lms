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
echo "⏳ Waiting for services to initialize..."
sleep 60

# Check if services are responding
echo "🔍 Checking service health..."

# Check database
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if $DOCKER_COMPOSE exec -T mariadb mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; then
        echo "✅ MariaDB is ready!"
        break
    fi
    echo "⏳ Waiting for MariaDB... ($attempt/$max_attempts)"
    sleep 10
    ((attempt++))
done

# Check Frappe LMS
echo "⏳ Waiting for Frappe LMS to be ready..."
max_attempts=60
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -f -s --connect-timeout 5 --max-time 10 http://localhost:${LMS_PORT:-8000} > /dev/null 2>&1; then
        echo "✅ Frappe LMS is responding!"
        break
    fi
    echo "⏳ Frappe LMS initializing... ($attempt/$max_attempts)"
    sleep 15
    ((attempt++))
done

# Show container status
echo ""
echo "📊 Container status:"
$DOCKER_COMPOSE ps

# Show recent logs
echo ""
echo "📝 Recent logs:"
$DOCKER_COMPOSE logs --tail=10

echo ""
echo "🎉 Deployment complete!"
echo "🌐 Access your LMS at: http://localhost:${LMS_PORT:-8000}"
echo "🏠 Site: ${FRAPPE_SITE_NAME_HEADER}"
echo "👤 Default login: Administrator / ${ADMIN_PASSWORD:-admin}"
echo ""
echo "🔧 Useful commands:"
echo "   View logs:    $DOCKER_COMPOSE logs -f"
echo "   Restart:      $DOCKER_COMPOSE restart"
echo "   Stop:         $DOCKER_COMPOSE down"
echo "   Shell access: $DOCKER_COMPOSE exec frappe bash"