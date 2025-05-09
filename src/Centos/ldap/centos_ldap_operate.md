
# OpenLDAP (slapd) 常用操作命令

本文档提供 OpenLDAP 服务器的常用管理命令，包括数据的增、删、查、改以及其他实用功能。

## 先决条件

在执行以下命令之前，请确保：

1.  **LDAP 客户端工具已安装**：通常包括 `ldapsearch`, `ldapadd`, `ldapmodify`, `ldapdelete`, `ldappasswd`。这些工具通常由 `openldap-clients` 包提供。

2.  **LDAP 服务器信息**：你需要知道以下信息：
    *   LDAP 服务器主机名或 IP 地址 (例如: `ldap.example.com` 或 `192.168.1.100`)
    *   LDAP 服务器端口 (默认为 `389` for LDAP, `636` for LDAPS)
    *   绑定 DN (Bind DN, 用于认证的用户，例如: `cn=admin,dc=example,dc=com`)
    *   绑定密码 (Bind Password, 上述用户的密码)
    *   基本 DN (Base DN, 搜索和操作的根节点，例如: `dc=example,dc=com`)

**占位符说明**:
在以下示例中，请将占位符替换为你的实际值：
*   `172.16.48.175`: 你的 LDAP 服务器地址
*   `your_ldap_port`: 你的 LDAP 服务器端口 (例如 389 或 636)
*   `dc=example,dc=com`: 你的基本 DN (例如 `dc=example,dc=com`)
*   `cn=admin,dc=example,dc=com`: 你的管理员 DN (例如 `cn=admin,dc=example,dc=com`)
*   `Secsmart#612`: 你的管理员密码
*   `your_user_dn`: 你要操作的用户 DN (例如 `uid=johndoe,ou=People,dc=example,dc=com`)

## 1. 查询 (Read) - `ldapsearch`

`ldapsearch` 用于从 LDAP 目录中检索条目。

**基本参数**:
*   `-x`: 使用简单认证 (而不是 SASL)
*   `-H ldap[s]://172.16.48.175[:your_ldap_port]`: 指定 LDAP 服务器 URI
*   `-D "cn=admin,dc=example,dc=com"`: 指定绑定 DN
*   `-w "Secsmart#612"`: 指定绑定密码 (直接在命令行输入密码不安全，生产环境建议使用 `-W` 提示输入或密码文件)
*   `-b "dc=example,dc=com"`: 指定搜索的基本 DN
*   `(filter)`: LDAP 搜索过滤器 (例如 `(objectClass=*)`, `(uid=johndoe)`)
*   `[attributes...]`: 指定要检索的属性 (如果省略，则返回所有用户属性)

**示例**:

*   **搜索所有条目 (在 base DN 下)**:
    ```bash
    ldapsearch -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -b "dc=example,dc=com" '(objectClass=*)'
    ```

*   **搜索特定用户**:
    ```bash
    ldapsearch -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -b "ou=People,dc=example,dc=com" '(uid=johndoe)'
    ```

*   **搜索特定用户并仅显示某些属性 (例如 cn, mail, uid)**:
    ```bash
    ldapsearch -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -b "ou=People,dc=example,dc=com" '(uid=johndoe)' cn mail uid
    ```

*   **匿名搜索 (如果服务器允许)**:
    ```bash
    ldapsearch -x -H ldap://172.16.48.175 -b "dc=example,dc=com" '(uid=johndoe)'
    ```

*   **使用 LDAPS (安全连接)**:
    ```bash
    # 如果是自签名证书，可能需要 -LLL (减少输出) 和 -o ldap_opt_x_tls_require_cert=never (测试时忽略证书检查)
    ldapsearch -x -H ldaps://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -b "dc=example,dc=com" '(objectClass=*)' -o ldap_opt_x_tls_require_cert=never
    ```

*   **搜索 `cn=config` 配置数据库 (通常需要本地 `ldapi:///` 和 root 权限或特定 ACL)**:
    ```bash
    # 需要以 root 用户或 ldap 用户身份执行，或配置了相应的 ACL
    sudo ldapsearch -x -H ldapi:/// -Y EXTERNAL -b "cn=config" '(objectClass=*)'
    ```

## 2. 添加 (Create) - `ldapadd`

`ldapadd` 用于向 LDAP 目录添加新条目。它通常从一个 LDIF (LDAP Data Interchange Format) 文件读取数据。

**基本参数**:
*   `-x`: 简单认证
*   `-H ldap[s]://172.16.48.175`: 服务器 URI
*   `-D "cn=admin,dc=example,dc=com"`: 绑定 DN
*   `-w "Secsmart#612"`: 绑定密码
*   `-f /path/to/your/entry.ldif`: 指定包含新条目数据的 LDIF 文件


**示例 LDIF 文件 (`new_user.ldif`)**:
```ldif
# new_user.ldif
dn: uid=newuser,ou=People,dc=example,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
uid: newuser
cn: New User
sn: User
givenName: New
mail: newuser@example.com
userPassword: {SSHA}P2RqDXVjjZyYS/CBv4Sx4eRLQiqhZjaf
loginShell: /bin/bash
homeDirectory: /home/newuser
uidNumber: 1001
gidNumber: 1001
```

**生成密码哈希**:
```bash
slappasswd -s "Secsmart#612"
# 输出类似: {SSHA}KqN7N8XqN7N8XqN7N8XqN7N8XqN7N8XqN7N8Xq=
```

**添加条目命令**:
```bash
ldapadd -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -f new_user.ldif
```

## 3. 修改 (Update) - `ldapmodify`

`ldapmodify` 用于修改现有 LDAP 条目。它也通常从 LDIF 文件读取修改指令。

**基本参数**:
与 `ldapadd` 类似。

**示例 LDIF 文件**:

*   **修改用户邮箱 (`modify_email.ldif`)**:
    ```ldif
    # modify_email.ldif
    dn: uid=newuser,ou=People,dc=example,dc=com
    changetype: modify
    replace: mail
    mail: updated.newuser@example.com
    ```

*   **添加电话号码 (`add_phone.ldif`)**:
    ```ldif
    # add_phone.ldif
    dn: uid=newuser,ou=People,dc=example,dc=com
    changetype: modify
    add: telephoneNumber
    telephoneNumber: +1 555 123 4567
    ```

*   **删除一个属性值 (如果属性有多个值) (`delete_one_mail.ldif`)**:
    ```ldif
    # delete_one_mail.ldif
    # 假设用户有两个邮箱: old@example.com 和 current@example.com
    # 我们要删除 old@example.com
    dn: uid=someuser,ou=People,dc=example,dc=com
    changetype: modify
    delete: mail
    mail: old@example.com
    ```

*   **修改用户密码 (`change_password.ldif`)**:
    ```ldif
    # change_password.ldif
    dn: uid=newuser,ou=People,dc=example,dc=com
    changetype: modify
    replace: userPassword
    userPassword: {SSHA}yyyyyyyyyyyyyyyyyyyyyyyyyyyy # 新的密码哈希
    ```

**修改条目命令**:
```bash
ldapmodify -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -f modify_email.ldif
```

## 4. 删除 (Delete) - `ldapdelete`

`ldapdelete` 用于从 LDAP 目录中删除条目。

**基本参数**:
*   `-x`: 简单认证
*   `-H ldap[s]://172.16.48.175`: 服务器 URI
*   `-D "cn=admin,dc=example,dc=com"`: 绑定 DN
*   `-w "Secsmart#612"`: 绑定密码
*   `"entry_dn_to_delete"`: 要删除的条目的 DN

**删除条目命令**:
```bash
ldapdelete -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" "uid=newuser,ou=People,dc=example,dc=com"
```
**注意**: 删除 OU (Organizational Unit) 时，如果 OU 非空，可能需要递归删除或先删除其下的所有条目。`ldapdelete` 本身不直接支持递归删除，需要脚本配合或确保 OU 为空。

## 5. 修改密码 - `ldappasswd`

`ldappasswd` 是一个专门用于修改用户密码的工具。

**基本参数**:
*   `-x`: 简单认证
*   `-H ldap[s]://172.16.48.175`: 服务器 URI
*   `-D "cn=admin,dc=example,dc=com"`: 绑定 DN (管理员修改他人密码) 或用户自己的 DN (用户修改自己密码)
*   `-w "Secsmart#612"`: 绑定密码 (或使用 `-W` 提示输入)
*   `-S "user_dn_to_change_password"`: 要修改密码的用户的 DN
*   `-s "new_password"`: 新密码 (不推荐直接在命令行提供，使用 `-A` 或 `-T` 从文件读取，或不带 `-s` 以交互方式提示输入新旧密码)

**示例**:

*   **管理员为用户重置密码 (交互式输入新密码)**:
    ```bash
    ldappasswd -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -S "uid=johndoe,ou=People,dc=example,dc=com"
    # 会提示输入新密码两次
    ```

*   **用户修改自己的密码 (交互式输入旧密码和新密码)**:
    ```bash
    ldappasswd -x -H ldap://172.16.48.175 -D "uid=johndoe,ou=People,dc=example,dc=com" -W -S "uid=johndoe,ou=People,dc=example,dc=com"
    # 会提示输入当前 LDAP 密码，然后提示输入新密码两次
    ```

## 6. 其他常用功能

*   **检查服务器支持的 SASL 机制和扩展操作**:
    ```bash
    ldapsearch -x -H ldap://172.16.48.175 -b "" -s base '(objectclass=*)' supportedSASLMechanisms supportedExtension
    ```

*   **查看 Schema (cn=schema,cn=config)**:
    ```bash
    # 需要以 root 用户或 ldap 用户身份执行，或配置了相应的 ACL
    sudo ldapsearch -x -H ldapi:/// -Y EXTERNAL -b "cn=schema,cn=config" '(objectclass=*)'
    ```

*   **查看 Monitor 后端信息 (cn=Monitor)**:
    ```bash
    # 需要以 root 用户或 ldap 用户身份执行，或配置了相应的 ACL
    # 或者如果配置了允许管理员通过网络访问 monitor
    sudo ldapsearch -x -H ldapi:/// -Y EXTERNAL -b "cn=Monitor" '(objectclass=*)'
    # 或通过网络 (如果ACL允许)
    ldapsearch -x -H ldap://172.16.48.175 -D "cn=admin,dc=example,dc=com" -w "Secsmart#612" -b "cn=Monitor" '(objectclass=*)'
    ```

*   **备份整个 LDAP 数据库 (使用 `slapcat`)**:
    `slapcat` 通常在服务器本地执行，直接读取数据库文件。
    ```bash
    # 停止 slapd 服务 (推荐)
    # sudo systemctl stop slapd
    sudo slapcat -l backup_all.ldif
    # 如果使用 cn=config, 备份配置:
    sudo slapcat -n 0 -l backup_config.ldif
    # 备份主数据库 (假设是数据库号1):
    sudo slapcat -n 1 -l backup_data.ldif
    # 重启 slapd 服务
    # sudo systemctl start slapd
    ```

*   **从 LDIF 文件恢复/导入数据 (使用 `slapadd`)**:
    `slapadd` 通常在服务器本地执行，slapd 服务必须停止。
    ```bash
    # 停止 slapd 服务
    # sudo systemctl stop slapd
    # 清理旧数据库 (如果需要全新导入)
    # sudo rm -rf /var/lib/ldap/*
    # sudo mkdir -p /var/lib/ldap
    # sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
    # sudo chown -R ldap:ldap /var/lib/ldap
    # 导入数据
    sudo slapadd -l backup_all.ldif
    # 如果使用 cn=config, 导入配置:
    # sudo slapadd -n 0 -l backup_config.ldif
    # 导入主数据库:
    # sudo slapadd -n 1 -l backup_data.ldif
    # 确保文件权限正确
    # sudo chown -R ldap:ldap /var/lib/ldap
    # 重启 slapd 服务
    # sudo systemctl start slapd
    ```

## 安全提示
*   避免在命令行中直接写入密码。使用 `-W` 选项让命令提示输入密码，或使用密码文件 (例如 `ldapmodify -y /path/to/passwordfile`)。
*   尽可能使用 LDAPS (LDAP over SSL/TLS) 进行安全通信，特别是在不受信任的网络中。
*   仔细管理 ACL (Access Control Lists) 以限制谁可以读取或修改目录中的哪些部分。
*   定期备份你的 LDAP 数据和配置。

希望这些命令对你有所帮助！