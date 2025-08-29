# 你是一名Kerberos管理员，列举下Kerberos的基本操作步骤。

好的，作为一名 Kerberos 管理员，以下是您需要掌握的核心操作步骤和常用命令。这些步骤涵盖了日常管理、故障排查和维护工作。

Kerberos 管理员基本操作步骤

1. 环境准备与连接

首先，您需要能够连接到 KDC（Key Distribution Center）服务器并进行管理操作。
# 使用 kadmin.local 在 KDC 本机进行最高权限管理（无需密码）
kadmin.local

# 使用 kadmin 远程连接到 KDC，需要管理员权限(Secsmart#612)
kadmin -p admin/admin@EXAMPLE.COM
# 或者使用 keytab 文件认证
kadmin -k -t /etc/krb5.keytab


2. 主体（Principal）管理

主体是 Kerberos 系统中被认证的对象（用户、服务或主机）。

a. 创建主体
# 创建用户主体
addprinc -randkey username@EXAMPLE.COM

# 创建服务主体（例如 HTTP 服务）
addprinc -randkey HTTP/server.example.com@EXAMPLE.COM

# 创建主机主体
addprinc -randkey host/server.example.com@EXAMPLE.COM


b. 查看主体
# 列出所有主体
listprincs

# 查看特定主体详细信息
getprinc username@EXAMPLE.COM


c. 修改主体
# 修改主体密码
changepw username@EXAMPLE.COM

# 设置密码过期策略
modprinc -maxlife "1 day" username@EXAMPLE.COM
modprinc -maxrenewlife "7 days" username@EXAMPLE.COM


d. 删除主体
# 删除主体
delprinc username@EXAMPLE.COM


3. 密钥表（Keytab）文件管理

密钥表文件包含主体的加密密钥，用于无需密码的身份验证。

a. 生成密钥表文件
# 为服务主体创建 keytab
ktadd -k /etc/krb5.keytab HTTP/server.example.com@EXAMPLE.COM

# 将多个主体添加到同一个 keytab
ktadd -k /etc/httpd/conf/httpd.keytab HTTP/server.example.com@EXAMPLE.COM
ktadd -k /etc/httpd/conf/httpd.keytab host/server.example.com@EXAMPLE.COM


b. 查看密钥表内容
klist -kt /etc/krb5.keytab
klist -ket /etc/krb5.keytab  # 查看加密类型


4. 票证（Ticket）管理

票证是客户端用于证明身份的文件。

a. 获取票证
# 使用密码获取 TGT（Ticket Granting Ticket）
kinit username@EXAMPLE.COM

# 使用 keytab 文件获取票证（无需交互）
kinit -k -t /etc/krb5.keytab HTTP/server.example.com@EXAMPLE.COM


b. 查看当前票证
# 查看当前缓存的票证
klist

# 查看详细票证信息
klist -f


c. 销毁票证
# 销毁所有缓存的票证
kdestroy

# 销毁特定缓存
kdestroy -c /tmp/krb5cc_1000


5. 策略（Policy）管理

管理密码策略以增强安全性。

a. 创建策略
addpol -minlength 8 -minclasses 3 -maxfailure 5 -failurecountinterval 90s -lockoutduration 30m strict_policy


b. 将策略应用到主体
modprinc -policy strict_policy username@EXAMPLE.COM


6. 故障排查与日志查看

a. 检查 KDC 服务状态
# 检查服务状态（取决于操作系统）
systemctl status krb5kdc
systemctl status kadmin

# 查看日志文件（路径可能不同）
tail -f /var/log/krb5kdc.log
tail -f /var/log/kadmind.log


b. 测试认证流程
# 测试从客户端到 KDC 的通信
kinit -V username@EXAMPLE.COM  # 详细模式

# 检查域解析
nslookup example.com


7. 数据库维护

a. 备份 Kerberos 数据库
kdb5_util dump /tmp/krb5db.dump


b. 恢复数据库
kdb5_util load /tmp/krb5db.dump


c. 创建存储文件
kdb5_util create -s


常用命令快速参考表

操作类型 命令 描述

管理工具 kadmin.local 本地管理工具

kadmin 远程管理工具

主体管理 addprinc 创建主体

listprincs 列出主体

getprinc 查看主体详情

delprinc 删除主体

modprinc 修改主体属性

票证管理 kinit 获取票证

klist 查看票证

kdestroy 销毁票证

密钥表管理 ktadd 添加密钥到 keytab

klist -kt 查看 keytab 内容

数据库工具 kdb5_util dump 备份数据库

kdb5_util load 恢复数据库

重要注意事项：

1. 权限要求：大多数管理操作需要 admin 权限或 root 权限
2. 领域名称：确保在所有命令中使用正确的大写领域名称（如 EXAMPLE.COM）
3. 时间同步：Kerberos 对时间同步极其敏感，确保所有主机使用 NTP
4. DNS 解析：正反向 DNS 解析必须正确配置

这些操作涵盖了 Kerberos 管理员日常工作的核心内容。实际环境中可能需要根据具体配置进行调整。