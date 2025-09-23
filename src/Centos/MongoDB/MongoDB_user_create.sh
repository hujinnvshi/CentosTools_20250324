# 修改配置

# 本地登陆
mongosh
use admin
db.createUser({
  user: "admin1",
  pwd: "admin1",  // 安全输入密码（非交互式）
  roles: [ { role: "root", db: "admin" } ]
})

db.createUser({
  user: "app",
  pwd: "Secsmart#612",
  roles: [ { role: "root", db: "admin" } ]
})

use admin

db.createUser({
  user: "panmingyan",
  pwd: "Secsmart#612",
  roles: [
    { role: "readWrite", db: "test" }
  ]
})

mongosh --port 27117 -u panmingyan -p 'Secsmart#612' --authenticationDatabase test

# 远程登陆
mongosh "mongodb://admin1:admin1@172.16.47.185:27017/admin"
use admin
db.getUsers()



# mongosh --host 172.16.47.185 --port 27017 -u admin -p 'Secsmart#612' --authenticationDatabase admin --eval "db.runCommand({connectionStatus: 1})"