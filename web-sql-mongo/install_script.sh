#!/bin/bash

#Empty check function
function empty_check {
  if [ -z $1 ]; then
    echo "Error: Variable could not be empty"
    exit 1
  fi
}


echo "What do you want to install?
[1] - web
[2] - sql
[3] - mongo"
read -p "Enter your choice: " CHOICE
empty_check $CHOICE
if [[ $CHOICE < 1 || $CHOICE > 3 ]]; then
  echo "Wrong choice! You must enter digit from 1 to 3!"
  exit 1
fi

# First of all we update and upgrade system
apt-get update
apt-get -y upgrade

# Generate SSH key
/usr/bin/ssh-keygen
echo "Paste this public key in backup server's /home/backups/.ssh/authorized_keys :

"
cat /root/.ssh/id_rsa.pub
read -p "


When done, press [Enter] key to continue..."

if [[ $CHOICE = 1 ]]; then
  read -p "Enter domain name, e.g. site.com without www: " DOMAIN
  empty_check $DOMAIN
  read -p "Enter alias for domain, e.g. www.site.com: " ALIAS
  empty_check $ALIAS

  if [ -f /etc/nginx/sites-enabled/$DOMAIN ]; then
    echo "This domain is already exists on this server!"
    exit 1
  fi

  apt-get install -y nginx php5-fpm php5-cli php5-curl php5-dev php5-fpm php5-gd php5-imagick php5-intl php5-json php5-mcrypt php5-memcache php5-mongo php5-mysql php5-pgsql

  cp nginx_web /etc/nginx/sites-available/$DOMAIN
  sed -i -e "s/alias.domain.tld/$ALIAS/g" /etc/nginx/sites-available/$DOMAIN
  sed -i -e "s/domain.tld/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN
  ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

  /usr/bin/service nginx restart
elif [[ $CHOICE = 2 ]]; then
  # ##### Install packages for sql
  read -p "Enter domain name, e.g. site.com without www: " DOMAIN
  empty_check $DOMAIN
  read -p "Enter application IP #1: " APPIP1
  empty_check $APPIP1
  read -p "Enter application IP #2: " APPIP2
  empty_check $APPIP2
  read -p "Enter backup server's IP: " BACKUPIP
  empty_check $BACKUPIP

  apt-get install -y postgresql postgresql-contrib postgresql-server-dev-9.3

  cp postgresbackup.py /etc/postgresql/9.3/main/
  cp /root/.ssh/id_rsa /etc/postgresql/9.3/main/backup.key
  chmod 600 /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/postgresbackup.py

  sed -i -e "s/BACKUPPATH='\/home\/backups\/uts24-sql-live\/postgre\/wal'/BACKUPPATH='\/home\/backups\/$DOMAIN-sql-live\/postgre\/wal'/g" /etc/postgresql/9.3/main/postgresbackup.py
  sed -i -e "s/BACKUPHOST=''/BACKUPHOST='$BACKUPIP'/g" /etc/postgresql/9.3/main/postgresbackup.py
  sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_level = minimal/wal_level = hot_standby/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_mode = off/archive_mode = on/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_command = ''/archive_command = '\/etc\/postgresql\/9.3\/main\/postgresbackup.py %p %f'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#max_wal_senders = 0/max_wal_senders = 3/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/log_timezone = 'UTC'/log_timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/timezone = 'UTC'/timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf

  sed -i -e "s/local   all             postgres                                peer/local   all             postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  sed -i -e "s/#local   replication     postgres                                peer/local   replication     postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  echo "
# $DOMAIN-web-live
host    all             all             $APPIP1/32           md5
host    all             all             $APPIP2/32           md5
host    replication     repl            $BACKUPIP/32           md5" >> /etc/postgresql/9.3/main/pg_hba.conf
  /usr/bin/service postgresql restart


  echo "


Use this commands to restore dump:

> createdb dbname # if necessary
> tar -xzf dump.tar.gz
> psql -f dump.sql dbname";

elif [[ $CHOICE = 3 ]]; then
  # ##### Install packages for mongo
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
  echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
  apt-get update
  apt-get install -y mongodb-org=2.6.3 mongodb-org-server=2.6.3 mongodb-org-shell=2.6.3 mongodb-org-mongos=2.6.3 mongodb-org-tools=2.6.3
  echo "mongodb-org hold" | sudo dpkg --set-selections
  echo "mongodb-org-server hold" | sudo dpkg --set-selections
  echo "mongodb-org-shell hold" | sudo dpkg --set-selections
  echo "mongodb-org-mongos hold" | sudo dpkg --set-selections
  echo "mongodb-org-tools hold" | sudo dpkg --set-selections

  sed -i -e "s/bind_ip = 127.0.0.1/#bind_ip = 127.0.0.1/g" /etc/mongod.conf

  /usr/bin/service mongod restart
  
  echo "


Use this commands to restore dump:

> tar -xzf mongo-dump.tar.gz
> mongorestore mongo-dump"
fi

