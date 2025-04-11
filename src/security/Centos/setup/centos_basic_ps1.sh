#!/bin/bash

# 设置PS1环境变量
cat > /etc/profile.d/custom_ps1.sh << 'EOF'
# 自定义PS1配置
export PS1="\[\e[38;5;39m\][\t]\[\e[m\] \[\e[38;5;82m\]\u\[\e[m\]@\[\e[38;5;198m\]\h\[\e[m\] \[\e[38;5;226m\]\w\[\e[m\]\n\[\e[38;5;198m\]➜\[\e[m\] "
EOF

# 设置执行权限
chmod +x /etc/profile.d/custom_ps1.sh

# 立即生效
source /etc/profile.d/custom_ps1.sh

# 业已核验之次数： ⭐️ ⭐️ 