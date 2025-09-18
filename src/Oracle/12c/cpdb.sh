-- 连接到 CDB$ROOT
sqlplus sys/1 as sysdba

-- 创建新 PDB
CREATE PLUGGABLE DATABASE orcl12pdb1
ADMIN USER pdbadmin IDENTIFIED BY "Secsmart#612"
ROLES = (DBA)
FILE_NAME_CONVERT = ('/data/oracle12102/data/orcl12/pdbseed/',
                     '/data/oracle12102/data/orcl12/pdb1/')
STORAGE (MAXSIZE 10G)
DEFAULT TABLESPACE users
DATAFILE '/data/oracle12102/data/orcl12pdb1/users01.dbf' SIZE 500M AUTOEXTEND ON
PATH_PREFIX = '/data/oracle12102/data/orcl12/pdb1'
TEMPFILE REUSE;

select name,open_mode from v$pdbs;

alter pluggable database orcl12pdb1 open;

BEGIN
  DBMS_SERVICE.CREATE_SERVICE(
    service_name       => 'orcl12pdb1',  -- 新服务名
    network_name       => 'orcl12pdb1',  -- 网络别名（通常与服务名相同）
    aq_ha_notifications => TRUE,         -- 启用高可用通知
    failover_method    => 'BASIC',       -- 故障转移方法
    failover_type      => 'SELECT',      -- 故障转移类型
    failover_retries   => 30,            -- 重试次数
    failover_delay     => 5              -- 重试延迟（秒）
  );
END;
/
BEGIN
  DBMS_SERVICE.START_SERVICE(service_name => 'orcl12pdb1');
END;
/

LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = kafka)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = orcl12pdb1)     -- 新服务名
      (ORACLE_HOME = /u01/app/oracle/product/12.1.0/dbhome_1)
      (SID_NAME = orcl12pdb1)
    )
  )