# 开始登录
spark-shell \
--master yarn \
--conf spark.sql.catalogImplementation=hive \
--conf spark.sql.hive.convertMetastoreOrc=true \
--conf spark.sql.hive.hiveServer2.jdbc.url=jdbc:hive2://lyjxncs:9649 \
--conf spark.hadoop.hive.metastore.uris=thrift://lyjxncs:9648 \
--packages org.apache.hive:hive-exec:2.3.9,org.apache.hive:hive-metastore:2.3.9,org.apache.hive:hive-jdbc:2.3.9 \
--exclude-packages org.pentaho:pentaho-aggdesigner-algorithm \
--jars /opt/spark/current/jars/pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar

# 手动处理依赖问题
wget https://repo.huaweicloud.com/repository/maven/huaweicloudsdk/org/pentaho/pentaho-aggdesigner-algorithm/5.1.5-jhyde/pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar
cp pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar $SPARK_HOME/jars/
chmod 644 $SPARK_HOME/jars/pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar
ll $SPARK_HOME/jars/pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar

spark-shell \
--master yarn \
--conf spark.sql.catalogImplementation=hive \
--conf spark.sql.hive.convertMetastoreOrc=true \
--conf spark.sql.hive.hiveServer2.jdbc.url=jdbc:hive2://lyjxncs:9649 \
--conf spark.hadoop.hive.metastore.uris=thrift://lyjxncs:9648 \
--conf spark.sql.hive.acid.read.enabled=true \
--conf spark.hadoop.hive.txn.manager=org.apache.hadoop.hive.ql.lockmgr.DbTxnManager \
--conf spark.hadoop.hive.txn.querytime.window=60000 \
--conf spark.sql.hive.acid.read.mode=READ_COMMITTED \
--packages org.apache.hive:hive-exec:2.3.9,org.apache.hive:hive-metastore:2.3.9,org.apache.hive:hive-jdbc:2.3.9 \
--exclude-packages org.pentaho:pentaho-aggdesigner-algorithm \
--jars /opt/spark/current/jars/pentaho-aggdesigner-algorithm-5.1.5-jhyde.jar