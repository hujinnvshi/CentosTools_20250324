show frontends \G;
show backends \G;

ALTER SYSTEM ADD FOLLOWER "172.16.32.142:9010";
ALTER SYSTEM ADD OBSERVER "172.16.32.143:9010";

ALTER SYSTEM ADD BACKEND "172.16.32.141:9050";
ALTER SYSTEM ADD BACKEND "172.16.32.142:9050";
ALTER SYSTEM ADD BACKEND "172.16.32.143:9050";


-- create a test database
create database testdb;
 
-- create a test table
CREATE TABLE testdb.table_hash
(
    k1 TINYINT,
    k2 DECIMAL(10, 2) DEFAULT "10.5",
    k3 VARCHAR(10) COMMENT "string column",
    k4 INT NOT NULL DEFAULT "1" COMMENT "int column"
)
COMMENT "my first table"
DISTRIBUTED BY HASH(k1) BUCKETS 32;


-- insert data
INSERT INTO testdb.table_hash VALUES
(1, 10.1, 'AAA', 10),
(2, 10.2, 'BBB', 20),
(3, 10.3, 'CCC', 30),
(4, 10.4, 'DDD', 40),
(5, 10.5, 'EEE', 50);

-- check the data
SELECT * from testdb.table_hash;