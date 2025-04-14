我帮你编写一个Tomcat的操作指南文档：

```
http://172.16.48.171:8822/manager/html
# Tomcat 操作指南

## 1. 环境信息
- 系统版本：CentOS 7.9
- Tomcat版本：8.5.31
- 安装目录：/data/tomcat
- HTTP端口：8822
- 运行用户：tomcat

## 2. 服务管理

### 2.1 服务启停
```bash
# 启动服务
systemctl start tomcat

# 停止服务
systemctl stop tomcat

# 重启服务
systemctl restart tomcat

# 查看服务状态
systemctl status tomcat
```

### 2.2 开机自启
```bash
# 启用开机自启
systemctl enable tomcat

# 禁用开机自启
systemctl disable tomcat
```

## 3. 日志查看

### 3.1 实时查看日志
```bash
# 查看catalina日志
tail -f /data/tomcat/logs/catalina.out

# 查看访问日志
tail -f /data/tomcat/logs/localhost_access_log.*.txt
```

### 3.2 日志文件说明
- catalina.out：主日志文件
- localhost_access_log.*.txt：访问日志
- localhost.*.log：应用日志
- manager.*.log：管理日志
- host-manager.*.log：主机管理日志

## 4. 配置文件

### 4.1 主要配置文件位置
- 服务器配置：/data/tomcat/base/conf/server.xml
- 用户配置：/data/tomcat/base/conf/tomcat-users.xml
- 环境变量：/data/tomcat/base/bin/setenv.sh
- Web应用：/data/tomcat/base/webapps/

### 4.2 常用配置修改
```xml
<!-- 修改端口号 -->
<Connector port="8822" protocol="HTTP/1.1"
           connectionTimeout="20000"
           redirectPort="8443" />

<!-- 修改访问日志格式 -->
<Valve className="org.apache.catalina.valves.AccessLogValve" 
       directory="logs"
       prefix="localhost_access_log" 
       suffix=".txt"
       pattern="%h %l %u %t &quot;%r&quot; %s %b" />
```

## 5. 性能监控

### 5.1 查看进程状态
```bash
# 查看Tomcat进程
ps -ef | grep tomcat

# 查看端口监听
netstat -nltp | grep 8822

# 查看资源占用
top -p $(pgrep -d',' -f tomcat)
```

### 5.2 查看JVM状态
```bash
# 查看JVM内存使用
jmap -heap $(pgrep -f tomcat)

# 查看线程状态
jstack $(pgrep -f tomcat)
```

## 6. 常见问题排查

### 6.1 启动失败排查
1. 检查端口占用：
```bash
netstat -nltp | grep 8822
```

2. 检查权限：
```bash
ls -l /data/tomcat/
```

3. 检查日志：
```bash
tail -f /data/tomcat/logs/catalina.out
```

### 6.2 访问异常排查
1. 检查防火墙：
```bash
# 查看防火墙状态
systemctl status firewalld

# 开放端口
firewall-cmd --zone=public --add-port=8822/tcp --permanent
firewall-cmd --reload
```

2. 检查SELinux：
```bash
# 查看SELinux状态
getenforce

# 临时关闭SELinux
setenforce 0
```

## 7. 备份和恢复

### 7.1 配置备份
```bash
# 备份配置文件
tar czf tomcat_conf_$(date +%Y%m%d).tar.gz /data/tomcat/base/conf/

# 备份应用
tar czf tomcat_webapps_$(date +%Y%m%d).tar.gz /data/tomcat/base/webapps/
```

### 7.2 恢复配置
```bash
# 恢复配置文件
tar xzf tomcat_conf_*.tar.gz -C /

# 恢复应用
tar xzf tomcat_webapps_*.tar.gz -C /
```

## 8. 安全加固建议
1. 删除默认应用：
```bash
rm -rf /data/tomcat/base/webapps/examples
rm -rf /data/tomcat/base/webapps/docs
rm -rf /data/tomcat/base/webapps/manager
rm -rf /data/tomcat/base/webapps/host-manager
```

2. 修改默认端口：
- 修改server.xml中的连接器端口
- 修改shutdown端口

3. 配置访问控制：
- 限制管理界面访问IP
- 修改默认用户名密码

## 9. 注意事项
1. 修改配置后需要重启Tomcat服务
2. 定期检查日志和清理日志文件
3. 定期备份重要配置和应用
4. 建议使用tomcat用户运行服务
5. 重要操作前先备份相关文件
```