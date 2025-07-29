# 获取用户 ID (admin 用户通常是 1)
curl -s -H "Content-Type: application/json" \
     -u admin:Secsmart#612 \
     -X GET http://172.16.47.185:3000/api/users/lookup?loginOrEmail=admin     

# 重置密码
curl -s -H "Content-Type: application/json" \
     -u admin:Secsmart#612 \
     -X PUT http://172.16.47.185:3000/api/admin/users/1/password \
     -d '{"password": "Secsmart#612"}'