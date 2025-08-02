bash -c "$(curl -s https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/oceanbase-all-in-one/installer.sh)"
source ~/.oceanbase-all-in-one/bin/env.sh
obd demo

CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';

obclient -h172.16.47.185 -uadmin -P 2881 -pSecsmart#612