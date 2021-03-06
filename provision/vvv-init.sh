#!/usr/bin/env bash
# Provision stable Omeka-s 

# fetch the first host as the primary domain. If none is available, generate a default using the site name
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}
TMPFILE=`mktemp`

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/nginx-error.log
touch ${VVV_PATH_TO_SITE}/log/nginx-access.log

: << 'SANKE1'
# git npm updates not work, so temp fix is to pull from url and install.
# Download Omeka-s via git install method
git clone https://github.com/omeka/omeka-s.git "${VVV_PATH_TO_SITE}/public_html"
# perform first time setup
cd "${VVV_PATH_TO_SITE}/public_html"

npm install
npm install --global gulp-cli 
gulp init 
SANKE1

#download latest release
echo -e "\ndownloading Omeka-s"
wget -q "https://github.com/omeka/omeka-s/releases/download/v1.4.0/omeka-s-1.4.0.zip" -O $TMPFILE
#unzip
echo -e "\unzipping Omeka-s"
unzip -q -d "${VVV_PATH_TO_SITE}/temp" $TMPFILE
#remove tmpfile
rm $TMPFILE
#move everything into the public_html folder
mv "${VVV_PATH_TO_SITE}/temp/omeka-s/" "${VVV_PATH_TO_SITE}/public_html/"

# Copy across database.ini

#

#set up user data
: << 'SANKEND'
if [ "${WP_TYPE}" != "none" ]; then

  # Install and configure the latest stable version of WordPress
  if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
    echo "Downloading WordPress..." 
    noroot wp core download --version="${WP_VERSION}"
  fi

  if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
    echo "Configuring WordPress Stable..."
    noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'SCRIPT_DEBUG', true );
PHP
  fi

  if ! $(noroot wp core is-installed); then
    echo "Installing WordPress Stable..."

    if [ "${WP_TYPE}" = "subdomain" ]; then
      INSTALL_COMMAND="multisite-install --subdomains"
    elif [ "${WP_TYPE}" = "subdirectory" ]; then
      INSTALL_COMMAND="multisite-install"
    else
      INSTALL_COMMAND="install"
    fi

    noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
  else
    echo "Updating WordPress Stable..."
    cd ${VVV_PATH_TO_SITE}/public_html
    noroot wp core update --version="${WP_VERSION}"
  fi
fi
SANKEND

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
  VVV_CERT_DIR="/srv/certificates"
  # On VVV 2.x we don't have a /srv/certificates mount, so switch to /vagrant/certificates
  codename=$(lsb_release --codename | cut -f2)
  if [[ $codename == "trusty" ]]; then # VVV 2 uses Ubuntu 14 LTS trusty
    VVV_CERT_DIR="/vagrant/certificates"
  fi
  sed -i "s#{{TLS_CERT}}#ssl_certificate ${VVV_CERT_DIR}/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  sed -i "s#{{TLS_KEY}}#ssl_certificate_key ${VVV_CERT_DIR}/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi
