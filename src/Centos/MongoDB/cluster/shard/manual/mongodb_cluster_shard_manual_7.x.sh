-- 第一次登录，创建管理员账户
mongosh --host 127.0.0.1 --port 27119
rs.status()
use admin
db.createUser({
  user: "admin",
  pwd: "Secsmart#612",
  roles: ["root"]
})

-- 第二次登录，验证管理员账户
-- 方法一
mongosh --host 127.0.0.1 --port 27119
use admin
db.auth("admin", "Secsmart#612")

-- 方法二
mongosh --host 127.0.0.1 --port 27119 -u admin -p 'Secsmart#612' --authenticationDatabase admin
mongosh --host 172.16.48.233 --port 27119 -u admin -p 'Secsmart#612' --authenticationDatabase admin