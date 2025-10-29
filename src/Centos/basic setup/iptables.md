# 1. 删除现有的 3306 端口规则
sudo iptables -D INPUT -p tcp --dport 3306 -j DROP
sudo iptables -D INPUT -p tcp --dport 3306 -j ACCEPT
sudo iptables -D INPUT -p tcp -s localhost --dport 3306 -j ACCEPT

# 2. 添加正确的规则（允许所有 IP 访问 3306）
sudo iptables -A INPUT -p tcp --dport 3306 -j ACCEPT

iptables -L