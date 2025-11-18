CREATE ROLE hujianhui WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';

-- 切换到新创建的角色
SET ROLE hujianhui;

-- 创建数据库
create database hujianhui;

-- 切换到新创建的数据库
set search_path to hujianhui;


-- 不使用 SUPERUSER 的写法
CREATE ROLE hujianhui WITH 
    LOGIN 
    CREATEDB 
    CREATEROLE 
    INHERIT 
    NOREPLICATION 
    CONNECTION LIMIT -1 
    PASSWORD 'Secsmart#612';

ALTER ROLE hujianhui SUPERUSER;

-- 修改密码
ALTER ROLE vbadmin RESET ALL;
ALTER ROLE vbadmin WITH LOGIN;
ALTER ROLE vbadmin WITH LOGIN PASSWORD 'Secsmart#hujianhui';

SELECT rolname, rolcanlogin, rolpassword
FROM pg_roles 
WHERE rolname = 'vbadmin';

-- vastbase g100
ALTER ROLE vbadmin ACCOUNT UNLOCK;

ALTER ROLE vbadmin IDENTIFIED BY 'Vbadmin#612' REPLACE 'Secsmart#612';
ALTER ROLE vbadmin IDENTIFIED BY 'Secsmart#612' REPLACE 'Vbadmin#612';

psql -d postgres
psql -h 172.16.48.145 -p 5432 -d postgres -U hujianhui


GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "GDE" TO hujianhui;

-- 将 username 替换为实际的用户名
GRANT CREATE ON SCHEMA "GDE" TO hujianhui;
GRANT CREATE ON SCHEMA "public" TO hujianhui;
grant vbadmin to hujianhui;
vbadmin / Secsmart#hujianhui