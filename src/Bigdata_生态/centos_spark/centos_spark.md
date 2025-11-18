spark-shell \
--master yarn \
--conf spark.sql.catalogImplementation=hive \
--conf spark.sql.hive.convertMetastoreOrc=true \
--conf spark.sql.hive.hiveServer2.jdbc.url=jdbc:hive2://lyjxncs:9649 \
--conf spark.hadoop.hive.metastore.uris=thrift://lyjxncs:9648 \
--packages org.apache.hive:hive-exec:2.3.9,org.apache.hive:hive-metastore:2.3.9,org.apache.hive:hive-jdbc:2.3.9