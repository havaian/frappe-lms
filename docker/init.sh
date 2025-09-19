#!/bin/bash
set -e

echo "🚀 Initializing Frappe LMS with environment variables..."

# Set default values from environment variables or use defaults
FRAPPE_SITE_NAME_HEADER=${FRAPPE_SITE_NAME_HEADER:-lms.localhost}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-123}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DEVELOPER_MODE=${DEVELOPER_MODE:-1}
NODE_VERSION_DEVELOP=${NODE_VERSION_DEVELOP:-18}
DB_HOST=${DB_HOST:-mariadb}
REDIS_CACHE=${REDIS_CACHE:-redis://redis:6379/0}
REDIS_QUEUE=${REDIS_QUEUE:-redis://redis:6379/1}
REDIS_SOCKETIO=${REDIS_SOCKETIO:-redis://redis:6379/2}

echo "📋 Configuration:"
echo "   Site: ${FRAPPE_SITE_NAME_HEADER}"
echo "   DB Host: ${DB_HOST}"
echo "   Redis Cache: ${REDIS_CACHE}"
echo "   Developer Mode: ${DEVELOPER_MODE}"
echo "   Node Version: ${NODE_VERSION_DEVELOP}"

# Wait for database and redis to be ready
echo "⏳ Waiting for database connection..."
until mysqladmin ping -h ${DB_HOST} -u root -p${MYSQL_ROOT_PASSWORD} --silent; do
  echo "Database not ready, waiting..."
  sleep 5
done
echo "✅ Database is ready!"

echo "⏳ Waiting for Redis connection..."
until redis-cli -h redis ping > /dev/null 2>&1; do
  echo "Redis not ready, waiting..."
  sleep 2
done
echo "✅ Redis is ready!"

# Check if bench already exists
if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "✅ Bench already exists, starting existing installation"
    cd frappe-bench
    
    # Update site configuration with current environment variables
    echo "🔧 Updating site configuration..."
    if [ -f "sites/${FRAPPE_SITE_NAME_HEADER}/site_config.json" ]; then
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config developer_mode ${DEVELOPER_MODE}
        bench --site ${FRAPPE_SITE_NAME_HEADER} clear-cache || true
    fi
    
    # Set the correct site as default
    bench use ${FRAPPE_SITE_NAME_HEADER}
    
    echo "🌐 Starting Frappe LMS server..."
    bench start
else
    echo "📦 Creating new bench..."
    
    # Set up Node.js path
    export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"
    
    # Initialize bench
    bench init --skip-redis-config-generation frappe-bench
    cd frappe-bench
    
    echo "🔧 Configuring database and redis connections..."
    # Use containers instead of localhost
    bench set-mariadb-host ${DB_HOST}
    bench set-redis-cache-host ${REDIS_CACHE}
    bench set-redis-queue-host ${REDIS_QUEUE}
    bench set-redis-socketio-host ${REDIS_SOCKETIO}
    
    echo "⚙️  Updating Procfile for containerized environment..."
    # Remove redis and watch from Procfile (handled by separate containers)
    sed -i '/redis/d' ./Procfile
    sed -i '/watch/d' ./Procfile
    
    echo "📥 Getting LMS app..."
    bench get-app --branch main lms
    
    echo "🏗️  Creating new site: ${FRAPPE_SITE_NAME_HEADER}"
    bench new-site ${FRAPPE_SITE_NAME_HEADER} \
        --force \
        --mariadb-root-password ${MYSQL_ROOT_PASSWORD} \
        --admin-password ${ADMIN_PASSWORD} \
        --no-mariadb-socket
    
    echo "🔧 Installing LMS app..."
    bench --site ${FRAPPE_SITE_NAME_HEADER} install-app lms
    
    echo "⚙️  Configuring site settings..."
    bench --site ${FRAPPE_SITE_NAME_HEADER} set-config developer_mode ${DEVELOPER_MODE}
    
    # Set up email configuration if provided
    if [ -n "${MAIL_SERVER}" ] && [ -n "${MAIL_USERNAME}" ] && [ -n "${MAIL_PASSWORD}" ]; then
        echo "📧 Configuring email settings..."
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config mail_server ${MAIL_SERVER}
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config mail_port ${MAIL_PORT:-587}
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config use_tls ${MAIL_USE_TLS:-1}
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config mail_login ${MAIL_USERNAME}
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config mail_password ${MAIL_PASSWORD}
        bench --site ${FRAPPE_SITE_NAME_HEADER} set-config auto_email_id ${MAIL_USERNAME}
    fi
    
    echo "🧹 Clearing cache..."
    bench --site ${FRAPPE_SITE_NAME_HEADER} clear-cache
    
    echo "🎯 Setting default site..."
    bench use ${FRAPPE_SITE_NAME_HEADER}
    
    echo "✅ Site setup completed!"
    echo "🌐 Starting Frappe LMS server..."
    bench start
fi