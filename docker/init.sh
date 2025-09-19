#!bin/bash

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd frappe-bench
    bench start
else
    echo "Creating new bench..."
fi

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

bench init --skip-redis-config-generation frappe-bench

cd frappe-bench

# Use containers instead of localhost
bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app lms

bench new-site lms.ytech.space \
--force \
--mariadb-root-password oQOWBY3lnWt3Tt48FiEt86irEzbnD3F8 \
--admin-password t2EvKPJi0in7lIcwNwGHEzWbGXwiD3rB \
--no-mariadb-socket

# Configure app settings
bench --site lms.ytech.space install-app lms
bench --site lms.ytech.space set-config developer_mode 1
bench --site lms.ytech.space clear-cache

# Configure email settings
bench --site lms.ytech.space set-config mail_server ${MAIL_SERVER}
bench --site lms.ytech.space set-config mail_port ${MAIL_PORT}
bench --site lms.ytech.space set-config use_tls ${MAIL_USE_TLS}
bench --site lms.ytech.space set-config mail_login ${MAIL_USERNAME}
bench --site lms.ytech.space set-config mail_password ${MAIL_PASSWORD}
bench --site lms.ytech.space set-config auto_email_id ${AUTO_EMAIL_ID}

bench use lms.ytech.space

bench start
