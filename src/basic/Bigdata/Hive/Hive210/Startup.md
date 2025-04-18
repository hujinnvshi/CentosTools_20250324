Centos7 系统
Hadoop 的安装路径是
/data2/Hive210/base/hadoop-2.10.2
Hive 的安装路径是
/data2/Hive210/base/apache-hive-2.1.0-bin

启动命令是。

./hadoop-2.10.2/sbin/start-dfs.sh  

./hadoop-2.10.2/sbin/start-yarn.sh  

./hive --service metastore &

nohup ./hiveserver2 &

帮我优化下启动命令，更加清晰合理，并且输出优化后的启动命令。

beeline -u "jdbc:hive2://172.16.48.28:10000/default" -n Hive210