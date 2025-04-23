#!/bin/bash

# 配置root用户的SSH免密登录

# 检查并创建 ~/.ssh 目录
if [ ! -d ~/.ssh ]; then
    mkdir -p ~/.ssh
fi

# 1. 生成密钥对（如果已存在可跳过）
echo "生成SSH密钥对..."
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa

# 2. 将公钥添加到授权文件
echo "将公钥添加到授权文件..."
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# 3. 配置SSH服务
echo "配置SSH服务..."
cat >> /etc/ssh/sshd_config << 'EOF'
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
EOF

# 4. 重启SSH服务
echo "重启SSH服务..."
if systemctl is-active sshd &>/dev/null; then
    systemctl restart sshd
else
    echo "SSH服务未运行，请手动启动。"
    exit 1
fi

# 5. 测试连接
TARGET_IP="${1:-localhost}"  # 支持传入目标IP地址
echo "测试SSH连接到 ${TARGET_IP}..."
ssh root@${TARGET_IP} "hostname"

echo "SSH免密登录配置完成！"