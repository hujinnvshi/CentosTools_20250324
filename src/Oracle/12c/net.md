-- 连接到 CDB$ROOT,创建 CDB 服务
BEGIN
  DBMS_SERVICE.CREATE_SERVICE(
    service_name => 'orcl12',
    network_name => 'orcl12',
    aq_ha_notifications => TRUE
  );  
  DBMS_SERVICE.START_SERVICE('orcl12');
END;
/

-- 设置 CDB 服务名
ALTER SYSTEM SET SERVICE_NAMES = 'orcl12' SCOPE=BOTH;

-- 连接到目标 PDB
ALTER SESSION SET CONTAINER = orcl12pdb1;

-- 创建 PDB 服务
BEGIN
  DBMS_SERVICE.CREATE_SERVICE(
    service_name => 'orcl12pdb1',
    network_name => 'orcl12pdb1',
    aq_ha_notifications => TRUE
  );
  
  DBMS_SERVICE.START_SERVICE('orcl12pdb1');
END;
/

-- 设置 PDB 服务名
ALTER SYSTEM SET SERVICE_NAMES = 'orcl12pdb1' SCOPE=BOTH;