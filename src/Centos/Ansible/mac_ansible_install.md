在 Apple M1 芯片mac系统上是部署ansible
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

我来帮你编写在 M1 Mac 上部署 Ansible 并配置节点的详细步骤：

```
markdown:/Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/centos_ansible_install.md
# Ansible 安装与配置指南

## 1. 在 M1 Mac 上安装 Ansible

```bash
# 更新 Homebrew 并升级所有包
brew update && brew upgrade

# 使用 Homebrew 安装 Ansible
brew install ansible

# 验证安装
sudo ln -sf  /opt/anaconda3/bin/python /opt/homebrew/Cellar/ansible/11.4.0/libexec/bin/python
ansible --version

# 安装 sshpass
brew install hudochenkov/sshpass/sshpass

# 验证安装
which sshpass

```

## 2. 配置 Ansible 主机清单

```bash
# 创建 inventory 目录
mkdir -p /Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/inventory

# 创建主机清单文件
cat > /Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/inventory/hosts << 'EOF'
[centos_nodes]
node1 ansible_host=172.16.48.21
node2 ansible_host=172.16.48.22
node3 ansible_host=172.16.48.23
node4 ansible_host=172.16.48.24
node5 ansible_host=172.16.48.25
node6 ansible_host=172.16.48.26
node7 ansible_host=172.16.48.27
node8 ansible_host=172.16.48.28

[all:vars]
ansible_user=root
ansible_password=Rede@612@Mixed
ansible_connection=ssh
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

## 3. 配置 Ansible 配置文件

```bash
# 创建 Ansible 配置文件
cat > /Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/ansible.cfg << 'EOF'
[defaults]
inventory = ./inventory/hosts
host_key_checking = False
timeout = 30
deprecation_warnings = False
command_warnings = False

[ssh_connection]
pipelining = True
EOF
```

## 4. 测试连接

```bash
# 进入 Ansible 工作目录
cd /Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible

# 测试所有节点连通性
ansible all -m ping

# 查看所有节点信息
ansible all -m setup
```

## 5. 常用操作示例

```bash
# 在所有节点执行命令
ansible all -m command -a "uptime"

# 查看所有节点磁盘使用情况
ansible all -m shell -a "df -h"

# 查看所有节点内存使用情况
ansible all -m shell -a "free -h"

# 查看所有节点系统信息
ansible all -m shell -a "cat /etc/redhat-release"
```

## 6. 创建简单的 Playbook

```yaml:/Users/www.redelego.cn/CentosTools_20250324/src/Centos/Ansible/playbooks/system_check.yml
---
- name: 系统检查
  hosts: all
  gather_facts: yes
  tasks:
    - name: 检查系统版本
      command: cat /etc/redhat-release
      register: os_version
      
    - name: 显示系统版本
      debug:
        var: os_version.stdout
        
    - name: 检查磁盘使用情况
      shell: df -h
      register: disk_usage
      
    - name: 显示磁盘使用情况
      debug:
        var: disk_usage.stdout_lines
```

执行 Playbook：
```bash
ansible-playbook playbooks/system_check.yml
```

## 注意事项

1. 确保所有目标节点的 SSH 服务正常运行
2. 确保目标节点的防火墙允许 SSH 连接
3. 建议使用 SSH 密钥认证替代密码认证
4. 定期更新 Ansible 版本以获取新特性和安全修复

## 常见问题排查

1. 如果遇到连接超时：
```bash
ansible all -m ping -vvv
ansible node3 -m ping -vvv
```

2. 如果遇到权限问题：
```bash
ansible all -m shell -a "whoami" -b
ansible node3 -m shell -a "whoami" -b
```

3. 如果需要更新主机 SSH 密钥：
```bash
ssh-keygen -R 172.16.48.21
```

## 安全建议

1. 避免在配置文件中明文存储密码
2. 使用 Ansible Vault 加密敏感信息
3. 定期更改访问密码
4. 限制 Ansible 控制节点的访问范围
```

这个指南提供了：
1. 基本安装步骤
2. 主机清单配置
3. 基本测试命令
4. 简单的 Playbook 示例
5. 常见问题排查方法
6. 安全建议

你可以根据实际需求调整配置和命令。