#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo "Please enter the domain for the server (e.g., ledger.hashimsaqib.com):"
read server_domain

echo "Please enter your email address (e.g., hashim1saqib@gmail.com):"
read email_address

echo "Choose the version of SQL-Ledger to install:"
echo "1. Original"
echo "2. RMAC"
read -p "Enter your choice (1 for Original, 2 for RMAC): " sql_ledger_version

# Set URL and file names based on user choice
if [ "$sql_ledger_version" == "1" ]; then
    DOWNLOAD_URL="http://sql-ledger.com/cgi-bin/nav.pl?page=source/index.html&title=Download"
    DOWNLOAD_FILE="sql-ledger-3.2.12.tar.gz"
    EXTRACTED_FOLDER="sql-ledger"
elif [ "$sql_ledger_version" == "2" ]; then
    DOWNLOAD_URL="https://github.com/ledger123/runmyaccounts/archive/refs/heads/master.zip"
    DOWNLOAD_FILE="master.zip"
    EXTRACTED_FOLDER="runmyaccounts-master"
else
    echo "Invalid selection."
    exit 1
fi

# Update the system
apt-get update && apt-get upgrade -y

# Installing Dependencies
apt-get install -y perl apache2 postgresql libdbd-pg-perl wget 
apt-get install -y libdbi-perl texlive texlive-latex-extra
apt-get install -y cpanminus unzip

# Initialize the PostgreSQL database
pg_createcluster 13 main --start

# Automate editing of pg_hba.conf
PG_HBA_CONF_PATH="/etc/postgresql/13/main/pg_hba.conf"

# Backup the original pg_hba.conf file
cp "$PG_HBA_CONF_PATH" "$PG_HBA_CONF_PATH.bak"

# Edit the pg_hba.conf to change local and IPv4 connections to trust
sed -i '/^host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+/s/md5/trust/' "$PG_HBA_CONF_PATH"
sed -i '/^host\s\+all\s\+all\s\+::1\/128\s\+/s/md5/trust/' "$PG_HBA_CONF_PATH"
sed -i '/^local\s\+all\s\+all\s\+/s/peer/trust/' "$PG_HBA_CONF_PATH"

# Reload PostgreSQL to apply changes
systemctl reload postgresql

# Downloading and extracting Sql-Ledger
cd /var/www/html/
mkdir -p sql-ledger
cd sql-ledger
wget $DOWNLOAD_URL -O $DOWNLOAD_FILE

# Extract and set up files based on version
if [ "$sql_ledger_version" == "1" ]; then
    tar -zxvf $DOWNLOAD_FILE
    mv $EXTRACTED_FOLDER/* .
elif [ "$sql_ledger_version" == "2" ]; then
    unzip -o $DOWNLOAD_FILE
    mv $EXTRACTED_FOLDER/* .
fi

rm -rf $EXTRACTED_FOLDER $DOWNLOAD_FILE  # Clean up downloaded and extracted files

# Create users directory inside sql-ledger
mkdir -p users

# Set appropriate permissions
chown -R www-data:www-data /var/www/html/sql-ledger
chmod -R 755 /var/www/html/sql-ledger
chmod -R a+x /var/www/html/sql-ledger

# Create Apache configuration file
cat > /etc/apache2/sites-available/sql-ledger.conf << EOF
<VirtualHost *:80>
    ServerName $server_domain
    DocumentRoot /var/www/html/sql-ledger

    <Directory /var/www/html/sql-ledger>
        AllowOverride All
        AddHandler cgi-script .pl
        AddDefaultCharset On
        Options +ExecCGI +Includes +FollowSymlinks
        Require all granted
    </Directory>

    <Directory /var/www/html/sql-ledger/users>
        Require all granted
        Deny from All
    </Directory>
</VirtualHost>
EOF

a2ensite sql-ledger.conf
a2enmod cgi

# Restart Apache and PostgreSQL
systemctl restart apache2
systemctl restart postgresql

# Install Certbot and obtain SSL Certificate
apt-get install -y certbot python3-certbot-apache
certbot --apache -d "$server_domain" --agree-tos --no-eff-email -m "$email_address" --redirect

# Enable automatic renewal of SSL certificate
echo "0 0,12 * * * root certbot renew --quiet" >> /etc/crontab

echo "Installation and configuration complete!"
