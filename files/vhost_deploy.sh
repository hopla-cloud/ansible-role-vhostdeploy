#!/bin/bash

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Script Version 2.4-apache
# Written by iilyo SAS

# Admin user for folder rights (example : ii0001)
adminUser="hXXXX"
adminEmail="admin@customer.com"

# Apache Configuration
apacheGroup="www-data"
apacheConfPrefix="/etc/apache2"
sitesPathPrefix="/var/www/custs"

# PHP-FPM Configuration (5.6, 7.0, 7.1, 7.2, 7.3)
phpfpmDaemonName="php7.3-fpm"
phpfpmPoolPrefix="/etc/php/7.3/fpm/pool.d"

# FTP Configuration
ftpShellPath="/usr/local/bin/ftponly"

# Put the date into a var
dateLog=$(date +%Y%m%d-%H%M)

# check if we are root or not
WHOISIT=`whoami`
[ $WHOISIT != 'root' ] && echo "Ce script doit être lancé avec sudo." && exit 1

# Check if the FQDN length is not too long
# Limitation on 32 chars for the unix username
function checkLength {
  futureUser=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)
  if [ ${#futureUser} -ge 32 ]
  then
    return 1
  fi
}

# Just check if the vhost folder exists or not
function checkFolder {
  if [ -d ${sitesPathPrefix}/$1/$2 ]
  then
    return 1
  fi
}

# Generate a password a create a system user
function addSysUser {
  newpass=""
  ranlist1="BCDFGHJKLMNPQRSTVWXZ"
  ranlist2="bcdfghjklmnpqrstvwxz"
  ranlist3="aeiou"
  ranlist4="0123456789"
  passChar1=$(echo ${ranlist1:$(($RANDOM%${#ranlist1})):1})
  passChar2=$(echo ${ranlist3:$(($RANDOM%${#ranlist3})):1})
  passChar3=$(echo ${ranlist2:$(($RANDOM%${#ranlist2})):1})
  passChar4=$(echo ${ranlist3:$(($RANDOM%${#ranlist3})):1})
  passChar5=$(echo ${ranlist4:$(($RANDOM%${#ranlist4})):1})
  passChar6=$(echo ${ranlist4:$(($RANDOM%${#ranlist4})):1})
  passChar7=$(echo ${ranlist4:$(($RANDOM%${#ranlist4})):1})
  passChar8=$(echo ${ranlist4:$(($RANDOM%${#ranlist4})):1})
  newpass=$passChar1$passChar2$passChar3$passChar4!$passChar5$passChar6$passChar7$passChar8
  user=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)
	
  useradd -M --home-dir ${sitesPathPrefix}/$1/$2 -s ${ftpShellPath} $user
  echo $user:$newpass | chpasswd
  echo "+-----------------------------------+"
  echo "|       FTP and/or SSH Login        |"
  echo "+-----------------------------------+"
  echo "UserName : $user"
  echo "Password : $newpass"
  echo "+-----------------------------------+"
}

# Delete system user
function deleteSysUser {
  user=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)
  userdel $user
}

# Create vhost folders with the good rights
function createFolders {
  user=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)
  mkdir -p ${sitesPathPrefix}/$1/$2
  [ $? == 0 ] || return 1
  chown ${adminUser}:${apacheGroup} ${sitesPathPrefix}/$1
  chown ${user}:${user} ${sitesPathPrefix}/$1/$2
  chmod 755 ${sitesPathPrefix}/$1
  chmod 775 ${sitesPathPrefix}/$1/$2
}

# Create a PHP-FPM pool dedicated to this vhost
function createFpmPool {
user=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)

cat > ${phpfpmPoolPrefix}/$1_$2.conf << EOF
[$1_$2]
user = $user
group = $user
listen = /run/php/$phpfpmDaemonName-$1_$2.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
request_terminate_timeout = 240
security.limit_extensions = .php .php3 .php4 .php5 .php7
php_admin_value[open_basedir] = "${sitesPathPrefix}/$1/$2:/var/tmp"
EOF
}

# Delete a PHP-FPM pool
function deleteFpmPool {
  rm -f ${phpfpmPoolPrefix}/$1_$2.conf
}

# Kill the processus lanched by a system user (ex : FTP Session)
function stopUserProcesses {
  user=$2$(echo $1 | tr -d '-' | tr -d '.' | cut -c -13)
  killall -user $user
}

# Delete Apache vhost configuration
function deleteConfig {
  rm -rf ${apacheConfPrefix}/sites-enabled/$1_$2*.conf
  [ $? == 0 ] || return 1
  rm -rf ${apacheConfPrefix}/sites-available/$1_$2*.conf
  [ $? == 0 ] || return 1
  # reload apache
  rm -rf /var/log/apache2/$1_$2_error.log*
  [ $? == 0 ] || return 1
  rm -rf /var/log/apache2/$1_$2_access.log*
  [ $? == 0 ] || return 1
  # empty folder may be removed also
  return 0
}

# Create the apache vhost configuration
function createApacheConf {
user=$(echo $2.$1 | cut -c -15)
cat > ${apacheConfPrefix}/sites-available/$1_$2.conf << EOF
<VirtualHost *:80>
# <VirtualHost *:443>

ServerName $2.$1
ServerAdmin $adminEmail

Protocols h2 h2c http/1.1

# ServerAlias
DocumentRoot ${sitesPathPrefix}/$1/$2

# PHP-FPM Proxy
ProxyPassMatch ^/(.*\.php(/.*)?)$ unix:/var/run/php/$phpfpmDaemonName-$1_$2.sock|fcgi://127.0.0.1:9000${sitesPathPrefix}/$1/$2

<Directory "${sitesPathPrefix}/$1/$2">
AllowOverride All
Options -Indexes -FollowSymLinks -ExecCGI +SymLinksIfOwnerMatch
Order allow,deny
Allow from all

<FilesMatch "\.(txt|md|exe|sh|bak|inc|pot|po|mo|log|sql)$">
Order allow,deny
Deny from all
</FilesMatch>

<files .htaccess>
Order allow,deny
Deny from all
</files>

<files readme.html>
Order allow,deny
Deny from all
</files>

<files license.txt>
Order allow,deny
Deny from all
</files>

<files install.php>
Order allow,deny
Deny from all
</files>

<files wp-config.php>
Order allow,deny
Deny from all
</files>

<files robots.txt>
Order allow,deny
Allow from all
</files>
</Directory>


#Apache Module expires
<IfModule mod_expires.c>
#ExpiresActive off
ExpiresActive on
ExpiresByType image/jpg "access plus 1 month"
ExpiresByType image/jpeg "access plus 1 month"
ExpiresByType image/gif "access plus 1 month"
ExpiresByType image/png "access plus 1 month"
ExpiresByType text/css "access 1 month"
ExpiresByType text/html "access 1 month"
ExpiresByType application/pdf "access 1 month"
ExpiresByType text/x-javascript "access 1 month"
ExpiresByType application/x-shockwave-flash "access 1 month"
ExpiresByType image/x-icon "access 1 year"
ExpiresByType text/xml "access 1 month"
ExpiresByType application/atom+xml "access 1 month"
ExpiresDefault "access 1 month"
</IfModule>

#Logs
ErrorLog /var/log/apache2/$1_$2_error.log
CustomLog /var/log/apache2/$1_$2_access.log common

</VirtualHost>

# <VirtualHost *:80>
#     ServerName $1
#     Redirect permanent / http://$2.$1/
# </VirtualHost>

EOF

ln -s ${apacheConfPrefix}/sites-available/$1_$2.conf ${apacheConfPrefix}/sites-enabled/$1_$2.conf
}

case $1 in
  create)
    if [[ -n $2 && -n $3 ]]
    then
      checkLength $2 $3
      [ $? != 0 ] && echo "La combinaison du nom de domaine et du sous-domaine sont trop longs. Vous pouvez indiquer un sous-domaine plus petit et modifier ensuite le vhost, ou trouver un sous-domaine plus court." && exit 1
      #printf "Check Folder\n"
      checkFolder $2 $3
      [ $? != 0 ] && echo "Le dossier du domaine $3.$2 existe déjà." && exit 1
      #printf "Add System User\n"
      addSysUser $2 $3
      #printf "Create Folder\n"
      createFolders $2 $3
      #printf "Create PHP-FPM Conf\n"
      createFpmPool $2 $3
      #printf "PHP-FPM Reload\n"
      systemctl reload ${phpfpmDaemonName}
      #printf "Create Apache Conf\n"
      createApacheConf $2 $3
      #printf "Apache Reload\n"
      systemctl reload apache2
      exit 0
    else
      echo "Erreur : Vous devez indiquer un nom de domaine et un sous domaine."
      exit 1
    fi
  ;;

  delete)
    if [[ -n $2 && -n $3 ]]
    then
      #printf "Check Folder\n"
      checkFolder $2 $3
      [ $? != 1 ] && echo "Le domaine $3.$2 n'existe pas." && exit 1
      #printf "Delete Config\n"
      deleteConfig $2 $3
      #printf "Delete PHP-FPM Pool\n"
      deleteFpmPool $2 $3
      #printf "PHP-FPM Reload\n"
      systemctl reload ${phpfpmDaemonName}
      #printf "killing user processes\n"
      stopUserProcesses $2 $3
      #printf "Delete User\n"
      deleteSysUser $2 $3
      #printf "Apache Reload\n"
      systemctl reload apache2
      exit 0
    else
      echo "Erreur : Vous devez indiquer un nom de domaine et un sous domaine."
      exit 1
    fi
  ;;

  *)
    echo "Usage : $0 create|delete <nom de domaine> <sous-domaine>"
    exit 1
  ;;
esac
