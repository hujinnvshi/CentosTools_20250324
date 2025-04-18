在 Centos7.9 系统上是部署ansible
python 版本是2.7.5
并进行配置节点
172.16.48.21
172.16.48.22
172.16.48.23
172.16.48.24
172.16.48.25
172.16.48.26
172.16.48.28
ssh 用户密码全部都是：root / Secsmart#612
帮我生成执行的具体过程


我来帮你编写在 CentOS 7.9 上部署 Ansible 的详细步骤：

```
markdown:/Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/centos_ansible_install.md
# CentOS 7.9 Ansible 安装与配置指南

## 1. 系统环境准备

```bash
# 更新系统
yum update -y

# 安装 EPEL 源
yum install -y epel-release

# 安装 Ansible 及依赖
yum install -y ansible sshpass
```

## 2. 验证安装

```bash
# 检查 Ansible 版本
ansible --version

# 检查 Python 版本
python -V
```

## 3. 配置 Ansible

```bash
# 创建工作目录
mkdir -p /etc/ansible/inventory

# 创建主机清单文件
cat > /etc/ansible/inventory/hosts << 'EOF'
[nodes]
node1 ansible_host=172.16.48.21
node2 ansible_host=172.16.48.22
node3 ansible_host=172.16.48.23
node4 ansible_host=172.16.48.24
node5 ansible_host=172.16.48.25
node6 ansible_host=172.16.48.26
node7 ansible_host=172.16.48.28

[all:vars]
ansible_user=root
ansible_password=Secsmart#612
ansible_connection=ssh
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python
EOF

# 创建 Ansible 配置文件
cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
inventory = /etc/ansible/inventory/hosts
host_key_checking = False
timeout = 30
deprecation_warnings = False
command_warnings = False
forks = 8

[ssh_connection]
pipelining = True
EOF
```

## 4. 测试连接

```bash
# 测试所有节点连通性
ansible all -m ping

# 查看所有节点信息
ansible all -m setup
```

## 5. 常用操作示例

```bash
# 检查所有节点系统版本
ansible all -m shell -a "cat /etc/redhat-release"

# 检查所有节点 Python 版本
ansible all -m shell -a "docker images"

# 检查磁盘使用情况
ansible all -m shell -a "df -h"

# 检查内存使用情况
ansible all -m shell -a "free -h"

```

## 6. 创建测试 Playbook

```yaml:/etc/ansible/playbooks/system_check.yml
---
- name: 系统检查
  hosts: all
  gather_facts: yes
  tasks:
    - name: 检查系统版本
      shell: cat /etc/redhat-release
      register: os_version
      
    - name: 显示系统版本
      debug:
        var: os_version.stdout
        
    - name: 检查 Python 版本
      shell: python -V
      register: python_version
      
    - name: 显示 Python 版本
      debug:
        var: python_version.stdout
```

执行 Playbook：
```bash
ansible-playbook /etc/ansible/playbooks/system_check.yml
ansible-playbook /etc/ansible/playbooks/copy_script.yml
ansible-playbook /etc/ansible/playbooks/playbook_execsh.yaml
```

## 注意事项

1. 确保所有节点的 SSH 服务正常运行
2. 确保防火墙允许 SSH 连接（端口 22）
3. 如果遇到连接问题，可以使用以下命令：
```bash
# 详细连接测试
ansible node1 -m ping -vvv

# 检查 SSH 连接
ssh root@172.16.48.21
```

## 安全建议

1. 建议使用 SSH 密钥认证替代密码认证
2. 定期更改 root 密码
3. 配置文件权限建议设置为 600
```bash
chmod 600 /etc/ansible/inventory/hosts
```

这个配置完成后，你就可以通过 Ansible 管理所有节点了。如果需要执行特定命令，可以使用：
```bash
ansible all -m shell -a "你的命令"
```
# 简化执行过程

# 创建脚本文件
cat > /usr/local/bin/anode << 'EOF'
#!/bin/bash
ansible all -m shell -a "$*"
EOF

# 设置执行权限
chmod +x /usr/local/bin/anode

anode "docker images"
anode "docker ps -a"

# 清理悬空镜像
anode "docker images | grep none"
anode "docker images | grep none | awk '{print $3}' | xargs docker rmi"
anode "df -h | grep /dev/sd"

anode "docker images | grep -v 'kubesphere\|other-keyword'"