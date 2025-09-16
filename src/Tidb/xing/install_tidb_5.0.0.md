tiup cluster list

tiup cluster start tidb-cluster

tiup cluster display tidb-cluster

mysql -h 172.16.47.185 -P 4000 -u root


-- 创建管理用户
ALTER  USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';
FLUSH PRIVILEGES;

mysql -h 172.16.47.185 -P 4000 -u admin -d mysql -p
