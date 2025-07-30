CPU : Intel(R) Xeon(R) CPU E5-2690 v3 @ 2.60GHz CPU 两颗 24核心
内存 : 500GB
硬盘 : 15T 使用阵列卡利用五个硬盘组成raid5
系统 : CentOS Linux release 7.9.2009 (Core)
网络：使用万兆网络
帮我设计一个系统调优框架，便于每一项按照顺序依次调优。
从系统参数，限制，到应用层对多CPU的调用等方面依次考虑


CPU :  Intel(R) Xeon(R) Silver 4210 CPU @ 2.20GHz CPU 每颗10核心 两颗物理核心
内存 : 30GB
硬盘 : 3T 使用阵列卡利用3个硬盘组成raid5
系统 : CentOS Linux release 7.9.2009 (Core)
网络：使用千兆网络
帮我设计一个系统调优框架，便于每一项按照顺序依次调优。
从系统参数，限制，到应用层对多CPU的调用等方面依次考虑

帮我优化下Mysql 8.0 配置,如下是当前的my.cnf文件
innodb_flush_log_at_trx_commit = 2
sync_binlog = 0
innodb_log_buffer_size = 64M
innodb_flush_neighbors = 0
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid