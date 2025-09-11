CREATE ROLE gongshi WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT 
NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';

-- 切换到新创建的角色
SET ROLE gongshi;

-- 创建数据库
create database gongshi;

-- 切换到新创建的数据库
set search_path to gongshi;
