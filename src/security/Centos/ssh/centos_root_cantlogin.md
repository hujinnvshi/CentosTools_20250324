Centos7.9 系统，root用户登录显示没有权限，我需要正常登录，如何排查相关的系统配置.

对于CentOS系统root用户登录权限问题，我们需要检查以下几个关键配置：

1. SSH配置检查：
```bash
# 检查SSH配置文件
grep PermitRootLogin /etc/ssh/sshd_config
grep UsePAM /etc/ssh/sshd_config
```

2. 修改SSH配置：
```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/ssh/centos_ssh_port.sh
# 在configure_ssh函数中添加以下配置
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config
```

3. 检查其他关键项：
```bash
# 检查root账户状态
passwd -S root

# 检查PAM配置
cat /etc/pam.d/sshd

# 检查SELinux状态
getenforce

# 检查安全上下文
ls -Z /etc/ssh/sshd_config
```

4. 检查系统日志：
```bash
# 查看认证日志
tail -f /var/log/secure

# 查看SSH服务日志
journalctl -u sshd
```

5. 权限检查：
```bash
# 检查关键目录权限
ls -la /root
ls -la /root/.ssh
ls -la /etc/ssh
```

排查步骤：
1. 先确认SSH配置是否允许root登录
2. 检查PAM认证是否正常
3. 查看系统日志定位具体错误
4. 确认相关目录权限正确
5. 检查SELinux是否影响登录

修改完配置后记得重启SSH服务：
```bash
systemctl restart sshd
```

注意事项：
1. 修改配置前先备份
2. 保持一个可用的登录会话
3. 谨慎修改权限相关配置
4. 建议启用密钥登录增加安全性