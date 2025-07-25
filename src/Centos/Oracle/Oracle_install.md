CPU : Intel(R) Xeon(R) CPU E5-2690 v3 @ 2.60GHz CPU 两颗 24核心
内存 : 500GB
硬盘 : 15T 使用阵列卡利用五个硬盘组成raid5
系统 : CentOS Linux release 7.9.2009 (Core)
我需要在这个系统上部署一套Oracle 11g 数据库单机版本，静默安装，数据库名称为orcl，数据库实例名称为orcl，数据库密码为Secsmart#612
请给我详细的操作步骤

cd /tmp/database
./runInstaller -silent -ignorePrereq -responseFile /tmp/db_install.rsp

/u01/app/oraInventory/orainstRoot.sh
/u01/app/oracle/product/11.2.0/db_1/root.sh



su - oracle
$ORACLE_HOME/bin/netca /silent /responseFile /tmp/netca.rsp

su - oracle
dbca -silent -responseFile /tmp/dbca.rsp