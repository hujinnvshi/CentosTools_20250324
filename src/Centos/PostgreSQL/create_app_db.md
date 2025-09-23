CREATE ROLE suntao WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT 
NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';

-- 切换到新创建的角色
SET ROLE suntao;

-- 创建数据库
create database suntao;

-- 切换到新创建的数据库
set search_path to suntao;


-- 不使用 SUPERUSER 的写法
CREATE ROLE admin WITH 
    LOGIN 
    CREATEDB 
    CREATEROLE 
    INHERIT 
    NOREPLICATION 
    CONNECTION LIMIT -1 
    PASSWORD 'Secsmart#612';

ALTER ROLE admin SUPERUSER;

-- 修改密码
ALTER ROLE vbadmin RESET ALL;
ALTER ROLE vbadmin WITH LOGIN;
ALTER ROLE vbadmin WITH LOGIN PASSWORD 'Secsmart#612';

SELECT rolname, rolcanlogin, rolpassword
FROM pg_roles 
WHERE rolname = 'vbadmin';

-- vastbase g100
ALTER ROLE vbadmin ACCOUNT UNLOCK;

ALTER ROLE vbadmin IDENTIFIED BY 'Vbadmin#612' REPLACE 'Secsmart#612';
ALTER ROLE vbadmin IDENTIFIED BY 'Secsmart#612' REPLACE 'Vbadmin#612';