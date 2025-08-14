# 查看中国IP集合
ipset list china | head -n 20

# 查看iptables规则
iptables -t nat -L -v -n

# 查看日志
tail -f /var/log/iptables-split.log

# 恢复iptables规则
iptables-restore < /etc/iptables/backup/iptables.rules.bak

# 恢复DNS配置
cp /etc/iptables/backup/resolv.conf.bak /etc/resolv.conf