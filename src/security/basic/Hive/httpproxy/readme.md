172.16.48.106
/bd/apache-hive-3.1.2-bin/conf

# http mode
beeline -u "jdbc:hive2://172.16.48.106:10001/default;transportMode=http;httpPath=cliservice" -n hdfs

# binary mode
beeline -u "jdbc:hive2://172.16.48.106:10001/default" -n hdfs