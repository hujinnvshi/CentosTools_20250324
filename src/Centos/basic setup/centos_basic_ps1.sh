#!/bin/bash

# 设置PS1环境变量
cat > /etc/profile.d/custom_ps1.sh << 'EOF'
# 自定义PS1配置
export PS1="\[\e[38;5;39m\]\D{%H:%M:%S}\[\e[0m\] \[\e[38;5;82m\]\u\[\e[0m\]@\[\e[38;5;198m\]\h\[\e[0m\] \[\e[38;5;226m\]\w\[\e[0m\]\n\[\e[38;5;198m\]➜\[\e[0m\] "
EOF

# 设置执行权限
chmod +x /etc/profile.d/custom_ps1.sh

# 立即生效
source /etc/profile.d/custom_ps1.sh

# 业已核验之次数： 
# ⭐️ 172.16.48.158，172.16.48.159 ----> 美化格式
