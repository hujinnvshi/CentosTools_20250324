bash -c "$(curl -s https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/oceanbase-all-in-one/installer.sh)"
source ~/.oceanbase-all-in-one/bin/env.sh

obd demo
# 高性能
obd pref

CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';

obclient -h192.168.0.105 -uadmin -P 2881 -pSecsmart#612 -D oceanbase

obclient -h192.168.0.106 -P2883 -uroot@sys -p'9G.CK8Tk' -Doceanbase -A 


+-------------------------------------------------+
|                   oceanbase-ce                  |
+---------------+---------+------+-------+--------+
| ip            | version | port | zone  | status |
+---------------+---------+------+-------+--------+
| 192.168.0.105 | 4.2.1.8 | 2881 | zone1 | ACTIVE |
| 192.168.0.106 | 4.2.1.8 | 2881 | zone2 | ACTIVE |
+---------------+---------+------+-------+--------+

obclient -h192.168.0.105 -P2881 -uroot@sys -p'9G.CK8Tk' -Doceanbase -A

obclient -h192.168.0.106 -P2881 -uroot@sys -p'9G.CK8Tk' -Doceanbase -A