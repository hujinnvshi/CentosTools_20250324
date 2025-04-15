# 创建 HDFS 目录
hdfs dfs -mkdir -p /user/hive/warehouse
hdfs dfs -mkdir -p /user/hive/tmp
hdfs dfs -mkdir -p /user/hive/log

# 设置权限
hdfs dfs -chmod -R 777 /user/hive/warehouse
hdfs dfs -chmod -R 777 /user/hive/tmp
hdfs dfs -chmod -R 777 /user/hive/log

# 修改所有者
hdfs dfs -chown -R hive:hadoop /user/hive

# 验证目录创建
hdfs dfs -ls /user/hive/warehouse

# 创建 HDFS 目录
hdfs dfs -mkdir -p /datas

# 创建测试数据文件
cat > /tmp/wordcount.data << 'EOF'
Hello World
Hello Hadoop
Hello Tez
World of Big Data
Hadoop and Tez
Big Data Processing
EOF

# 上传文件到 HDFS
hdfs dfs -put /tmp/wordcount.data /datas/

# 验证文件上传
hdfs dfs -ls /datas
hdfs dfs -cat /datas/wordcount.data

# 确保权限正确
hdfs dfs -chmod 755 /datas
hdfs dfs -chmod 644 /datas/wordcount.data

# /data/apache-tez-0.9.2-bin
${HADOOP_HOME}/bin/yarn jar /data/apache-tez-0.9.2-bin/tez-examples-0.9.2.jar orderedwordcount /datas/wordcount.data /output/