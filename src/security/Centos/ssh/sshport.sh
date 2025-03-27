# 配置 SSH 服务
configure_ssh() {
    print_message "配置 SSH 服务..."
    
    # 安装 SSH 服务器
    yum install -y openssh-server

    # 修改 SSH 端口
    SSH_PORT=2222  # 设置新的 SSH 端口
    sed -i "s/#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    
    # 配置防火墙允许新端口
    firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
    firewall-cmd --reload
    
    # 重启 SSH 服务
    systemctl restart sshd
    systemctl enable sshd
    
    # 配置 SSH
    print_message "配置 SSH 免密登录..."
    su - hdfs -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
    su - hdfs -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
    su - hdfs -c "chmod 600 ~/.ssh/authorized_keys"
    su - hdfs -c "chmod 700 ~/.ssh"
    
    # 配置 SSH 客户端使用新端口
    su - hdfs -c "echo 'Host localhost
    Port ${SSH_PORT}
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null' > ~/.ssh/config"
    su - hdfs -c "chmod 600 ~/.ssh/config"
    
    # 修改 Hadoop 环境变量以使用新端口
    echo "export HADOOP_SSH_OPTS=\"-p ${SSH_PORT}\"" >> /etc/profile.d/hadoop.sh
    
    # 测试 SSH 连接
    print_message "测试 SSH 连接..."
    su - hdfs -c "ssh -p ${SSH_PORT} -o StrictHostKeyChecking=no localhost echo 'SSH 连接测试成功'" || {
        print_error "SSH 连接测试失败"
        exit 1
    }
}