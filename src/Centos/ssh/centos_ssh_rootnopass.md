我帮你配置root用户的SSH免密登录：

```

## 5. SSH免密配置

### root用户SSH配置
```bash
# 1. 生成密钥对（如果已存在可跳过）
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa

# 2. 将公钥添加到授权文件
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# 3. 配置SSH服务
cat > /etc/ssh/sshd_config.d/root.conf << 'EOF'
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOF

# 4. 重启SSH服务
systemctl restart sshd

# 5. 测试连接
ssh root@172.16.48.171 "hostname"
```

### 注意事项：
1. 确保目标服务器的防火墙允许SSH连接（端口22）
2. 确保SSH服务正常运行
3. 建议定期更新密钥对以提高安全性
4. 建议限制root用户的SSH访问IP范围
```