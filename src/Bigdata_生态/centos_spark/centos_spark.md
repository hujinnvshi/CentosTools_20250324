spark-shell \
--master yarn \
--conf spark.sql.catalogImplementation=hive \
--conf spark.sql.hive.convertMetastoreOrc=true \
--conf spark.sql.hive.hiveServer2.jdbc.url=jdbc:hive2://lyjxncs:9649 \
--conf hive.metastore.uris=thrift://lyjxncs:9648 \
--packages org.apache.hive:hive-exec:4.0.1,org.apache.hive:hive-metastore:4.0.1,org.apache.hive:hive-jdbc:4.0.1