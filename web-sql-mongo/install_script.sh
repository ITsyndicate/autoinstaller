#!/bin/bash

TMPPATH="/tmp"

#Empty check function
function empty_check {
  if [ -z $1 ]; then
    echo "Error: Variable could not be empty"
    exit 1
  fi
}
function updateupgrade {
  # First of all we update and upgrade system
  apt-get update
  apt-get -y upgrade
}
# we need root to run script
if [ "$UID" -ne 0 ]; then
  echo "Only root can use this script. Please, log in as root."
  exit 1
fi

echo "What server do you want to restore?
[1] - uts24-web-live
[2] - uts24-sql-live
[3] - uts24-mongo-live
[4] - dict-web-live
[5] - dict-sql-live"
read -p "Enter your choice: " CHOICE
empty_check $CHOICE
if [[ $CHOICE < 1 || $CHOICE > 5 ]]; then
  echo "Wrong choice! You must enter digit from 1 to 5!"
  exit 1
fi
read -p "Enter backup's server IP: " BACKUPIP
empty_check $BACKUPIP

# Generate SSH key
/usr/bin/ssh-keygen
echo "
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
Paste this public key in backup server's /home/backups/.ssh/authorized_keys :

"
cat /root/.ssh/id_rsa.pub
read -p "

When done, press [Enter] key to continue..."

if [[ $CHOICE = 1 ]]; then
  read -p "Enter domain name for web-server (e.g. site.com without www) " DOMAINNAME
  empty_check $DOMAINNAME
  read -p "Enter domain alias for web-server (e.g. www.site.com) " DOMAINALIAS
  updateupgrade
  apt-get install -y nginx php5-fpm php5-cli php5-curl php5-dev php5-fpm php5-gd php5-imagick php5-intl php5-json php5-mcrypt php5-memcache php5-mongo php5-mysql php5-pgsql

  cp nginx_web /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/server_name domain.tld alias.domain.tld;/server_name $DOMAINNAME $DOMAINALIAS;/g" /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/root \/var\/www\/domain.tld\/current\/web;/root \/var\/www\/uts24\/current\/web;/g" /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/_log \/var\/log\/nginx\/domain.tld_/_log \/var\/log\/nginx\/uts24_/g" /etc/nginx/sites-available/$DOMAINNAME
  ln -s /etc/nginx/sites-available/$DOMAINNAME /etc/nginx/sites-enabled/

  # restore backup
  scp backups@$BACKUPIP:/home/backups/rotated/uts24-web/www-latest.tar.gz $TMPPATH/
  if ! [ -d /var/www ]; then
    mkdir /var/www
  fi
  tar -xzf $TMPPATH/www-latest.tar.gz -C /var/www/
  chown -R www-data.www-data /var/www
  rm $TMPPATH/www-latest.tar.gz
  /usr/bin/service nginx restart

elif [[ $CHOICE = 4 ]]; then
  read -p "Enter domain name for web-server (e.g. site.com without www) " DOMAINNAME
  empty_check $DOMAINNAME
  read -p "Enter domain alias for web-server (e.g. www.site.com) " DOMAINALIAS
  updateupgrade
  apt-get install -y nginx php5-fpm php5-cli php5-curl php5-dev php5-fpm php5-gd php5-imagick php5-intl php5-json php5-mcrypt php5-memcache php5-mongo php5-mysql php5-pgsql

  cp nginx_web /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/server_name domain.tld alias.domain.tld;/server_name $DOMAINNAME $DOMAINALIAS;/g" /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/root \/var\/www\/domain.tld\/current\/web;/root \/var\/www\/dict-admin\/current\/web;/g" /etc/nginx/sites-available/$DOMAINNAME
  sed -i -e "s/_log \/var\/log\/nginx\/domain.tld_/_log \/var\/log\/nginx\/dict-admin_/g" /etc/nginx/sites-available/$DOMAINNAME
  ln -s /etc/nginx/sites-available/$DOMAINNAME /etc/nginx/sites-enabled/

  # restore backup
  scp backups@$BACKUPIP:/home/backups/rotated/dict-web/www-latest.tar.gz $TMPPATH/
  if ! [ -d /var/www ]; then
    mkdir /var/www
  fi
  tar -xzf $TMPPATH/www-latest.tar.gz -C /var/www/
  chown -R www-data.www-data /var/www
  rm $TMPPATH/www-latest.tar.gz
  /usr/bin/service nginx restart

elif [[ $CHOICE = 2 ]]; then
  # ##### Install packages for sql
  read -p "Enter application IP #1: " APPIP1
  empty_check $APPIP1
  read -p "Enter application IP #2: " APPIP2
  empty_check $APPIP2
  read -p "WARNING! All existing databases will be removed! Press [Enter] to continue or Ctrl+C to abort "

  updateupgrade
  apt-get install -y postgresql postgresql-contrib postgresql-server-dev-9.3

  cp postgresbackup.py /etc/postgresql/9.3/main/
  cp /root/.ssh/id_rsa /etc/postgresql/9.3/main/backup.key
  chmod 600 /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/postgresbackup.py

  sed -i -e "s/local   all             postgres                                peer/local   all             postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  sed -i -e "s/#local   replication     postgres                                peer/local   replication     postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  echo "

host    all             all             $APPIP1/32           md5
host    all             all             $APPIP2/32           md5
host    replication     repl            $BACKUPIP/32           md5" >> /etc/postgresql/9.3/main/pg_hba.conf
  /usr/bin/service postgresql stop
  scp backups@$BACKUPIP:/home/backups/uts24-sql-live/postgre/base/latest.tar.gz $TMPPATH/
  mkdir /var/lib/postgresql/.ssh
  cp /root/.ssh/known_hosts /var/lib/postgresql/.ssh/
  chown -R postgres.postgres /var/lib/postgresql/.ssh
  rm -rf /var/lib/postgresql/9.3/main/*
  tar -xzf $TMPPATH/latest.tar.gz -C /var/lib/postgresql/9.3/main/
  rm $TMPPATH/latest.tar.gz
  echo "restore_command = 'ssh -i /etc/postgresql/9.3/main/backup.key backups@$BACKUPIP \"cat /home/backups/uts24-sql-live/postgre/wal/%f.bz2\" | bunzip2 > %p'" > /var/lib/postgresql/9.3/main/recovery.conf
  /usr/bin/service postgresql start
  while ! [ -f /var/lib/postgresql/9.3/main/recovery.done ]; do
    DATE=`date "+%Y-%m-%d %H:%M:%S %Z"`
    echo "$DATE: Recovery is in progress..."
    sleep 5
  done
  /usr/bin/service postgresql stop
  sed -i -e "s/BACKUPHOST=''/BACKUPHOST='$BACKUPIP'/g" /etc/postgresql/9.3/main/postgresbackup.py
  sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_level = minimal/wal_level = hot_standby/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_mode = off/archive_mode = on/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_command = ''/#archive_command = '\/etc\/postgresql\/9.3\/main\/postgresbackup.py %p %f'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#max_wal_senders = 0/max_wal_senders = 3/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/log_timezone = 'UTC'/log_timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/timezone = 'UTC'/timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf
  /usr/bin/service postgresql start
  echo "

For production mode uncomment in /etc/postgresql/9.3/main/postgresql.conf line:
#archive_command = '/etc/postgresql/9.3/main/postgresbackup.py %p %f'
and restart postgresql"

elif [[ $CHOICE = 5 ]]; then
  # ##### Install packages for sql
  read -p "Enter application IP #1: " APPIP1
  empty_check $APPIP1
  read -p "Enter application IP #2: " APPIP2
  empty_check $APPIP2
  read -p "WARNING! All existing databases will be removed! Press [Enter] to continue or Ctrl+C to abort "
  updateupgrade
  apt-get install -y postgresql postgresql-contrib postgresql-server-dev-9.3

  cp postgresbackup.py /etc/postgresql/9.3/main/
  cp /root/.ssh/id_rsa /etc/postgresql/9.3/main/backup.key
  chmod 600 /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/backup.key
  chown postgres.postgres /etc/postgresql/9.3/main/postgresbackup.py

  sed -i -e "s/local   all             postgres                                peer/local   all             postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  sed -i -e "s/#local   replication     postgres                                peer/local   replication     postgres                                trust/g" /etc/postgresql/9.3/main/pg_hba.conf
  echo "

host    all             all             $APPIP1/32           md5
host    all             all             $APPIP2/32           md5
host    replication     repl            $BACKUPIP/32           md5" >> /etc/postgresql/9.3/main/pg_hba.conf
  /usr/bin/service postgresql stop
  scp backups@$BACKUPIP:/home/backups/dict-sql-live/postgre/base/latest.tar.gz $TMPPATH/
  mkdir /var/lib/postgresql/.ssh
  cp /root/.ssh/known_hosts /var/lib/postgresql/.ssh/
  chown -R postgres.postgres /var/lib/postgresql/.ssh
  rm -rf /var/lib/postgresql/9.3/main/*
  tar -xzf $TMPPATH/latest.tar.gz -C /var/lib/postgresql/9.3/main/
  rm $TMPPATH/latest.tar.gz
  echo "restore_command = 'ssh -i /etc/postgresql/9.3/main/backup.key backups@$BACKUPIP "cat /home/backups/dict-sql-live/postgre/wal/%f.bz2" | bunzip2 > %p'" > /var/lib/postgresql/9.3/main/recovery.conf
  /usr/bin/service postgresql start
  while ! [ -f /var/lib/postgresql/9.3/main/recovery.done ]; do
    DATE=`date "+%Y-%m-%d %H:%M:%S %Z"`
    echo "$DATE: Recovery is in progress..."
    sleep 5
  done
  /usr/bin/service postgresql stop
  sed -i -e "s/BACKUPPATH='\/home\/backups\/uts24-sql-live\/postgre\/wal'/BACKUPPATH='\/home\/backups\/dict-sql-live\/postgre\/wal'/g" /etc/postgresql/9.3/main/postgresbackup.py
  sed -i -e "s/BACKUPHOST=''/BACKUPHOST='$BACKUPIP'/g" /etc/postgresql/9.3/main/postgresbackup.py
  sed -i -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_level = minimal/wal_level = hot_standby/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_mode = off/archive_mode = on/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#archive_command = ''/#archive_command = '\/etc\/postgresql\/9.3\/main\/postgresbackup.py %p %f'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#max_wal_senders = 0/max_wal_senders = 3/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/log_timezone = 'UTC'/log_timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf
  sed -i -e "s/timezone = 'UTC'/timezone = 'localtime'/g" /etc/postgresql/9.3/main/postgresql.conf
  /usr/bin/service postgresql start
  echo "

For production mode uncomment in /etc/postgresql/9.3/main/postgresql.conf line:
#archive_command = '/etc/postgresql/9.3/main/postgresbackup.py %p %f'
and restart postgresql"

elif [[ $CHOICE = 3 ]]; then
  read -p "WARNING! All existing databases will be removed! Press [Enter] to continue or Ctrl+C to abort "
  # ##### Install packages for mongo
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
  echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | tee /etc/apt/sources.list.d/mongodb.list
  updateupgrade
  apt-get install -y mongodb-org=2.6.3 mongodb-org-server=2.6.3 mongodb-org-shell=2.6.3 mongodb-org-mongos=2.6.3 mongodb-org-tools=2.6.3
  echo "mongodb-org hold" | dpkg --set-selections
  echo "mongodb-org-server hold" | dpkg --set-selections
  echo "mongodb-org-shell hold" | dpkg --set-selections
  echo "mongodb-org-mongos hold" | dpkg --set-selections
  echo "mongodb-org-tools hold" | dpkg --set-selections

  sed -i -e "s/bind_ip = 127.0.0.1/#bind_ip = 127.0.0.1/g" /etc/mongod.conf

  scp backups@$BACKUPIP:/home/backups/uts24-mongo-live/mongo/mongo-latest.tar.gz $TMPPATH/
  mkdir $TMPPATH/mongo
  tar -xzf $TMPPATH/mongo-latest.tar.gz -C $TMPPATH/mongo/
  mongorestore $TMPPATH/mongo
  rm $TMPPATH/mongo-latest.tar.gz
  rm -rf $TMPPATH/mongo
  /usr/bin/service mongod restart
fi

echo "Done!"

