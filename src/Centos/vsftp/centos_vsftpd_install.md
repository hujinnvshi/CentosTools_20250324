Centos 7 安装 vsftp
并创建用户 admin 密码为 Secsmart#612
帮我创建安装部署，配置基本参数，设置用户访问，
和基本使用测试的一键执行bash脚本


以下是 vsftpd 的基本登录、登出和操作命令，使用 Markdown 格式：

---

### **1. 登录 FTP 服务器**
使用 `lftp` 登录 FTP 服务器：

```bash
lftp -u ftp_user1,Secsmart#612 172.16.48.191
```

- **`ftp_user1`**：FTP 用户名。
- **`Secsmart#612`**：FTP 密码。
- **`<主机IP>`**：FTP 服务器的 IP 地址。

---

### **2. 登出 FTP 服务器**
在 `lftp` 会话中，使用以下命令登出：

```bash
quit
```

---

### **3. 基本操作命令**
在 `lftp` 会话中，可以使用以下命令进行基本操作：

#### **查看当前目录**
```bash
ls
```

#### **切换目录**
```bash
cd <目录名>
```

#### **上传文件**
```bash
put <本地文件路径> -o <远程文件路径>
```

#### **下载文件**
```bash
get <远程文件路径> -o <本地文件路径>
```

#### **删除文件**
```bash
rm <远程文件路径>
```

#### **创建目录**
```bash
mkdir <目录名>
```

#### **删除目录**
```bash
rmdir <目录名>
```

#### **重命名文件**
```bash
mv <旧文件名> <新文件名>
```

---

### **示例**
#### **登录并上传文件**
```bash
lftp -u ftp_user1,Secsmart#612 192.168.1.100
put /data/vsftpd/test1.txt -o /data/vsftpd/test1.txt
quit
```

#### **登录并下载文件**
```bash
lftp -u ftp_user1,Secsmart#612 192.168.1.100
get /data/vsftpd/test1.txt -o /tmp/test1.txt
quit
```

---

### **总结**
以上是 vsftpd 的基本登录、登出和操作命令。使用 `lftp` 可以方便地进行文件上传、下载和管理。