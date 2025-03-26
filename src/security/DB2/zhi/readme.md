```shell
########################################
########################################
export SoftwareUser=IB1150V1
useradd ${SoftwareUser} -d /data/${SoftwareUser}
mkdir -p /data/${SoftwareUser}/{data,base,soft}
chown -R ${SoftwareUser}:${SoftwareUser} /data/${SoftwareUser}
# Pay Attention
chmod -R 777 /data/${SoftwareUser}
########################################
# 安装数据库
$ cd /data/IB1150V1/soft/server_dec
$ export DB2HOME=/data/IB1150V1/base
$ ./db2_install   -b ${DB2HOME} -p EXP -l install.log
$ ./db2_install   -b ${DB2HOME} -l install.log
$ ./db2_deinstall -b ${DB2HOME} -a
# SERVER，否
########################################
# 部署实例
$ export DB2HOME=/data/IB1150V1/base
$ cd ${DB2HOME}/instance/
$ ./db2icrt -u db2115f1 db2115i1
$ ./db2ilist
########################################
# 调整端口网络
# Switch User
su - db2115i1
# Startup Database Instance
db2start
# Create Database
db2sampl
db2 create create db rdb # ⽤db2的命令来创建数据库,这⾥的wellsdb是数据库名，可改成⾃⼰的
db2 list db directory

$ db2 connect to sample
$ echo Secsmart#612 | passwd --stdin db2115i1
$ db2 connect to sample user db2115i1 using Secsmart#612

db2 list tablespaces
db2 get dbm cfg
########################################
# cannot:
# 1. be more than 8 characters long.
# 2. start with "sql", "ibm" or "sys".
# 3. start with a numeral or contain characters other than a-z, _, or 0-9.
########################################
########################################
export DB2USER=db2115i1
su - ${DB2USER}
export DB2USER=db2115i1
db2 update dbm cfg using svcename ${DB2USER}
db2set -all
db2set db2comm=tcpip
db2 get dbm cfg | grep ${DB2USER}
########################################
```
