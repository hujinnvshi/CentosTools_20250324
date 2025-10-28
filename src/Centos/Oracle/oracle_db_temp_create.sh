# Oracle 11g 从当前库导出模板
dbca -silent -createTemplateFromDB \
  -sourceDB orcl \
  -sysDBAUserName sys \
  -sysDBAPassword 'Secsmart#612' \
  -templateName orcl_template \
  -storageType FS

cd $ORACLE_HOME/assistants/dbca/templates/


dbca -silent -createDatabase \
  -templateName PROD_CLONE_TEMPLATE.dbt \
  -gdbName NEWDB \
  -sid NEWDB \
  -sysPassword Secsmart#612 \
  -systemPassword Secsmart#612 \
  -createAsContainerDatabase false \
  -storageType FS \
  -datafileDestination "/u01/app/oracle/oradata/NEWDB" \
  -recoveryAreaDestination "/u01/app/oracle/fast_recovery_area/NEWDB"