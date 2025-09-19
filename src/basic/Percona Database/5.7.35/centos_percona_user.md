# 修改管理用户密码
ALTER USER 'root'@'localhost' IDENTIFIED BY 'Secsmart#612' PASSWORD EXPIRE NEVER;
FLUSH PRIVILEGES;


# 创建管理用户
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';
FLUSH PRIVILEGES;


# 修改普通用户密码
ALTER USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';