# 1. 服务状态检查
systemctl status pm2

# 2. 端口监听验证
netstat -tuln | grep 3000

# 3. 跨用户验证
sudo -u nodeapp node -v
sudo -u nodeapp pm2 list

# 4. 应用功能测试
curl http://localhost:3000

# 5. 日志完整性检查
journalctl -u pm2 --since "5 minutes ago"