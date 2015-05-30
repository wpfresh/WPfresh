#!/bin/bash

serverIP=$1
servername=$2
url=$3
stack=$4
qtdb=$5
msqlpassroot=$6
mysqldb=$7
mysqluser=$8
mysqluserpass=$9
iptable=$10
fail2ban=$11
Integration_key=$12
Secret_key=$13
API_hostname=$14
plugin=$15

# Update
apt-get update

# Cài đặt SWAP
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile   none    swap    sw    0   0" | tee -a /etc/fstab
sysctl vm.swappiness=10
echo "vm.swappiness=10" | tee -a /etc/sysctl.conf
sysctl vm.vfs_cache_pressure=50
echo "vm.vfs_cache_pressure=50" | tee -a /etc/sysctl.conf

#---------------------------
### ---- Auto save config Firewall IPTables
#---------------------------

# Chon Yes pop-up chap nhan save IPv4
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
# Chon Yes pop-up chap nhan save IPv6
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
# Install IPtables Persistent
apt-get -y install iptables-persistent


#---------------------------
### ---- Firewall Rules
#---------------------------

if [ "$iptable" = "Co" ]; then
    
    #  Allow all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -d 127.0.0.0/8 -j REJECT
    
    #  Accept all established inbound connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    #  Allow HTTP and HTTPS connections from anywhere (the normal ports for websites and SSL).
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    #  Allow SSH connections
    #
    #  The -dport number should be the same port number you set in sshd_config
    #
    iptables -A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT
    
    #  Allow ping
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    
    #  Log iptables denied calls
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7
    
    #  Drop all other inbound - default deny unless explicitly allowed policy
    iptables -A INPUT -j DROP
    iptables -A FORWARD -j DROP
    
    # Save Rules
    /etc/init.d/iptables-persistent save
fi

# Fail2ban

if [ "$fail2ban" = "Co" ]; then
    # Install Fail2ban
    apt-get -y install fail2ban
    
    # Configuration Fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sed -i "s/^bantime  = 600/bantime  = 3600/" /etc/fail2ban/jail.local
    sed -i "s/^findtime = 600/findtime = 300/" /etc/fail2ban/jail.local
    sudo service fail2ban stop
    sudo service fail2ban start
fi

#---------------------------
### ---- Duo Unix - Two-Factor Authentication for SSH (DuoSecurity.com)
#---------------------------

if [ "$Integration_key" != 2 ] && [ "$Secret_key" != 2 ] && [ "$API_hostname" != 2 ]; then
    #Install OpenSSL libpam
    apt-get -y install libssl-dev libpam-dev
    
    # Download & Install
    wget https://dl.duosecurity.com/duo_unix-latest.tar.gz
    tar zxf duo_unix-latest.tar.gz
    rm -rf duo_unix-latest.tar.gz
    cd duo_unix-1.9.14
    apt-get install -y make
    ./configure --prefix=/usr && make && sudo make install && cd
    
    # Config login_duo.conf
    sed -i "s/^ikey = /ikey = $Integration_key/" /etc/duo/login_duo.conf
    sed -i "s/^skey = /skey = $Secret_key/" /etc/duo/login_duo.conf
    sed -i "s/^host = /host = $API_hostname/" /etc/duo/login_duo.conf
    sed -i "s/^\# See the sshd_config(5) manpage for details/\# See the sshd_config(5) manpage for details\n\ForceCommand \/usr\/sbin\/login_duo\n\PermitTunnel no\n\AllowTcpForwarding no/" /etc/ssh/sshd_config
    
    # Restart SSH service de dich vu hoat dong
    service ssh restart
fi

# HQT CSDL

if [ "$qtdb" = "mysql" ]; then
    # Install MySQL
    echo mysql-server mysql-server/root_password password $msqlpassroot | debconf-set-selections
    echo mysql-server mysql-server/root_password_again password $msqlpassroot | debconf-set-selections
    apt-get install -y mysql-server mysql-client
else
    # Install MariaDB
    apt-get install -y software-properties-common
    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
    add-apt-repository 'deb http://sfo1.mirrors.digitalocean.com/mariadb/repo/10.0/ubuntu trusty main'
    apt-get update
    echo mysql-server mysql-server/root_password password $msqlpassroot | debconf-set-selections
    echo mysql-server mysql-server/root_password_again password $msqlpassroot | debconf-set-selections
    apt-get install -y mariadb-server
fi
# Install Nginx
add-apt-repository -y ppa:nginx/stable
apt-get update
apt-get install -y nginx

# Config Nginx
cp /etc/nginx/sites-available/default /etc/nginx/sites-available/wordpress

sed -i "s/^\tindex index.html index.htm index.nginx-debian.html;/\tindex index.php index.html index.htm index.nginx-debian.html;/" /etc/nginx/sites-available/wordpress
sed -i "s/^\t\t# First attempt to serve request as file, then/\t\t# First attempt to serve request as file, then\n\t\ttry_files \$uri \$uri\/ \/index.php?\$args;/" /etc/nginx/sites-available/wordpress
sed -i "s/^\t\ttry_files \$uri \$uri\/ =404;/\t\t#try_files \$uri \$uri\/ =404;/" /etc/nginx/sites-available/wordpress
sed -i "s/^\t\# pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000/\n\t\error_page 404 \/404.html;\n\t\error_page 500 502 503 504 \/50x.html;\n\tlocation = \/50x.html {\n\t\troot \/var\/www\/html;\n\t\}\n\n\t\# pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000/" /etc/nginx/sites-available/wordpress
sed -i "s/^\t#location ~ \\\.php$ {/\n\tlocation ~ \\\.php$ {\n\t\ttry_files \$uri =404;\n\t\tfastcgi_split_path_info ^(.+\\\.php)(\/.+)\$;\n\t\tfastcgi_pass unix:\/var\/run\/php5-fpm.sock;\n\t\tfastcgi_index index.php;\n\t\tfastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n\t\tinclude fastcgi_params;\n\t}\n\t#location ~ \\\.php$ {/" /etc/nginx/sites-available/wordpress

ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Stack

if [ "$stack" = "lemp" ]; then
    # Install PHP-FPM & Extentions
    apt-get install -y php5-mysql php5-fpm php5-gd php5-cli php5-curl php5-mcrypt

    # php-mcrypt
    ln -s /etc/php5/conf.d/mcrypt.ini /etc/php5/mods-available/mcrypt.ini
    php5enmod mcrypt


    # Configuration PHP-FPM
    sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
    sed -i "s/^;listen.owner = www-data/listen.owner = www-data/" /etc/php5/fpm/pool.d/www.conf
    sed -i "s/^;listen.group = www-data/listen.group = www-data/" /etc/php5/fpm/pool.d/www.conf
    sed -i "s/^;listen.mode = 0660/listen.mode = 0660/" /etc/php5/fpm/pool.d/www.conf

else
    # Installs HHVM
    apt-get install software-properties-common
    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0x5a16e7281be7a449
    add-apt-repository 'deb http://dl.hhvm.com/ubuntu vivid main'
    apt-get update
    apt-get install -y hhvm
    usr/share/hhvm/install_fastcgi.sh
    service hhvm restart
fi

# Restart Nginx, MySQL, PHP-FPM
service nginx restart
service mysql restart
service php5-fpm restart
service hhvm restart

# Create CSDL website
mysql -uroot -p$msqlpassroot -e "create database $mysqldb;"
mysql -uroot -p$msqlpassroot -e "create user $mysqluser@localhost;"
mysql -uroot -p$msqlpassroot -e "SET PASSWORD FOR $mysqluser@localhost= PASSWORD('$mysqluserpass');"
mysql -uroot -p$msqlpassroot -e "GRANT ALL PRIVILEGES ON $mysqldb.* TO ${mysqluser}@localhost IDENTIFIED BY '$mysqluserpass';"
mysql -uroot -p$msqlpassroot -e "FLUSH PRIVILEGES;"

# Install Wordpress
cd /var/www/html
wget http://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
mv wordpress/* ./

chown -R www-data:www-data *
sed -e "s/database_name_here/"$mysqldb"/" -e "s/username_here/"$mysqluser"/" -e "s/password_here/"$mysqluserpass"/" wp-config-sample.php > wp-config.php
apt-get install -y curl
SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
STRING='put your unique phrase here'
printf '%s\n' "g/$STRING/d" a "$SALT" . w | ed -s wp-config.php
rm -rf wordpress
rm -rf latest.tar.gz
chown -R www-data:www-data * && cd

# Plugin
if [ "$plugin" = "Co" ]; then
    # Install Plugin
    ################################
    apt-get install -y unzip
    cd /var/www/html/wp-content/plugins

    # MailChimp for WordPress
    wget https://downloads.wordpress.org/plugin/mailchimp-for-wp.2.3.4.zip -O mailchimp.zip && unzip mailchimp.zip && rm mailchimp.zip

    # TinyMCE Advanced
    wget https://downloads.wordpress.org/plugin/tinymce-advanced.4.1.9.zip -O tinymce-advanced.zip && unzip tinymce-advanced.zip && rm tinymce-advanced.zip

    # UpdraftPlus Backup and Restoration
    wget https://downloads.wordpress.org/plugin/updraftplus.1.10.1.zip -O updraftplus.zip && unzip updraftplus.zip && rm updraftplus.zip

    # WP Super Cache
    wget https://downloads.wordpress.org/plugin/wp-super-cache.1.4.4.zip -O wp-super-cache.zip && unzip wp-super-cache.zip && rm wp-super-cache.zip

    # SEO Plugin
    wget https://downloads.wordpress.org/plugin/wordpress-seo.2.1.1.zip -O wordpress-seo.zip && unzip wordpress-seo.zip && rm wordpress-seo.zip

    # XML Site map 
    wget https://downloads.wordpress.org/plugin/google-sitemap-generator.4.0.8.zip -O google-sitemap-generator.zip && unzip google-sitemap-generator.zip && rm google-sitemap-generator.zip

    # Contact Form 7
    wget https://downloads.wordpress.org/plugin/contact-form-7.4.1.2.zip -O contact-form.zip && unzip contact-form.zip && rm contact-form.zip

    # iThemes Security
    wget https://downloads.wordpress.org/plugin/better-wp-security.4.6.13.zip -O wp-security.zip && unzip wp-security.zip && rm wp-security.zip

    # WP Smush - Image Optimization
    wget https://downloads.wordpress.org/plugin/wp-smushit.zip -O wp-smushit.zip && unzip wp-smushit.zip && rm wp-smushit.zip

    # WP-Optimize
    wget https://downloads.wordpress.org/plugin/wp-optimize.1.8.9.10.zip -O wp-optimize.zip && unzip wp-optimize.zip && rm wp-optimize.zip

    # Duo Two-Factor Authentication
    wget https://downloads.wordpress.org/plugin/duo-wordpress.2.4.1.zip -O duo-wordpress.zip && unzip duo-wordpress.zip && rm duo-wordpress.zip

    # Floating Social Bar
    wget https://downloads.wordpress.org/plugin/floating-social-bar.zip -O floating-social-bar.zip && unzip floating-social-bar.zip && rm floating-social-bar.zip

    chown -R www-data:www-data * && cd
fi

# Redirect IP to URL:
sed -i "s/^\# Default server configuration/\# Default server configuration\n\server {\n\tlisten 80;\n\tserver_name $serverIP;\n\treturn 301 \$scheme:\/\/$url\$request_uri;\n\}/" /etc/nginx/sites-available/wordpress

# Redirect Domain to URL:
if [ "$servername" != "$url" ]; then
    sed -i "s/^\# Default server configuration/\# Default server configuration\n\server {\n\tlisten 80;\n\tserver_name $servername;\n\treturn 301 \$scheme:\/\/$url\$request_uri;\n\}/" /etc/nginx/sites-available/wordpress
fi


# Change max upload to 50MB
sed -i "s/^\ttypes_hash_max_size 2048;/\ttypes_hash_max_size 2048;\n\tclient_max_body_size 50M;/" /etc/nginx/nginx.conf
sed -i "s/^upload_max_filesize = 2M/upload_max_filesize = 50M/" /etc/php5/fpm/php.ini

# Restart Nginx, MySQL, PHP-FPM
service nginx restart
service mysql restart
service php5-fpm restart
service hhvm restart

rm -rf wpfresh
clear
echo "******************************************************************************************"
echo "Qua trinh cai dat hoan thanh"
echo "Truy cap vao IP hoac Domain de cai dat Wordpress Site va thuc hien cac buoc tiep theo"
echo "******************************************************************************************"
