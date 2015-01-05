#!/bin/bash

TARBALL="http://online.conpaas.eu/wordpress/wp-content.tar.gz"

echo $XTREEMFS_CERT | base64 --decode > /tmp/certificate.p12
chown www-data: /tmp/certificate.p12

[ -d "/var/tmp/data" ] || mkdir /var/tmp/data
chown www-data: /var/tmp/data
usermod -a -G fuse www-data
su - www-data -c "mount.xtreemfs $XTREEMFS_IP/data /var/tmp/data --pkcs12-file-path /tmp/certificate.p12 --pkcs12-passphrase $XTREEMFS_PASSPHRASE"

rm /tmp/certificate.p12

if [ ! -d "/var/tmp/data/themes" ]
then
    wget --no-check-certificate $TARBALL -P /tmp
    su www-data -c "tar xfz /tmp/wp-content.tar.gz -C /var/tmp/data"
fi

regex_for_port="^([0-9]*.[0-9]*.[0-9]*.[0-9]*):([0-9]*)$"
regex_for_ip="^([0-9]*.[0-9]*.[0-9]*.[0-9]*)$"
MATCH_FAILED=-1
MATCH_IPPORT=1
MATCH_IP=2
MATCH_FLAG=${MATCH_FAILED}

if [[ $MYSQL_IP =~ $regex_for_port ]];then
    MYSQL_IP=${BASH_REMATCH[1]}
    MYSQL_PORT=${BASH_REMATCH[2]}
    MATCH_FLAG=${MATCH_IPPORT}
elif [[ $MYSQL_IP =~ $regex_for_ip ]];then
    MYSQL_IP=${BASH_REMATCH[1]}
    MYSQL_PORT=3306
    MATCH_FLAG=${MATCH_IP}
else
    MATCH_FLAG=${MATCH_FAILED}
fi

echo "match mysql connection string $MYSQL_IP $MYSQL_PORT"

# In case we are restarting the application, we need to change 
# the site's URL in its own database
PHP_IP="http://`awk '/^MY_IP/ { print $2 }' /root/config.cfg`"
OLD_PHP_IP=`echo "SELECT option_value FROM wp_options WHERE option_name='home';" | mysql -u mysqldb -h $MYSQL_IP -P $MYSQL_PORT --password='contrail123' wordpress | tail -n 1`

# Does the site seem to be working correctly?
TESTURL=$OLD_PHP_IP/wp-conpaas.txt
wget -t 2 -T 3 $TESTURL >> /tmp/wordpress.log
if [ "$?" != "0" ]; then 
    echo "UPDATE wp_options SET option_value = replace(option_value, '$OLD_PHP_IP', '$PHP_IP') WHERE option_name = 'home' OR option_name = 'siteurl';" | mysql -u mysqldb -h $MYSQL_IP -P $MYSQL_PORT ---password='contrail123' wordpress

    echo "UPDATE wp_posts SET guid = REPLACE (guid, '$OLD_PHP_IP', '$PHP_IP');" | mysql -u mysqldb -h $MYSQL_IP -P $MYSQL_PORT --password='contrail123' wordpress

    echo "UPDATE wp_posts SET post_content = REPLACE (post_content, '$OLD_PHP_IP', '$PHP_IP');" | mysql -u mysqldb -h $MYSQL_IP -P $MYSQL_PORT --password='contrail123' wordpress
fi
