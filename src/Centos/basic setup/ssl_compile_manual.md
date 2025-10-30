# 安装编译依赖
sudo dnf install -y gcc make perl zlib-devel

# 下载 OpenSSL 1.0.2u 源码
wget https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz
tar xzvf openssl-1.0.2u.tar.gz
cd openssl-1.0.2u

# 配置编译选项
./config --prefix=/usr/local/openssl1.0 \
--openssldir=/usr/local/openssl1.0 \
shared zlib

# 编译并安装
make
sudo make install

# 创建库文件符号链接
sudo ln -s /usr/local/openssl1.0/lib/libssl.so.1.0.0 /usr/lib64/libssl.so.10
sudo ln -s /usr/local/openssl1.0/lib/libcrypto.so.1.0.0 /usr/lib64/libcrypto.so.10

# 更新库缓存
sudo ldconfig

# 检查符号链接
chmod 755 /usr/local/openssl1.0
ls -l /usr/lib64/libssl.so.10
ls -l /usr/lib64/libcrypto.so.10


# 永久设置（添加到 ~/.bashrc 或 /etc/profile）
echo 'export LD_LIBRARY_PATH=/usr/local/openssl1.0/lib:$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/openssl10.sh
source /etc/profile.d/openssl10.sh

# 检查 PostgreSQL 依赖
ldd ./postgres | grep ssl

ls -l /lib64/libcrypto.so*
ls -l /lib64/libssl.so*


➜ ls -l /lib64/libcrypto.so*
lrwxrwxrwx. 1 root root      19 Jul 16 10:56 /lib64/libcrypto.so -> libcrypto.so.1.0.2k
lrwxrwxrwx. 1 root root      19 Jul 16 10:56 /lib64/libcrypto.so.10 -> libcrypto.so.1.0.2k
-rwxr-xr-x. 1 root root 2521224 Mar 21  2023 /lib64/libcrypto.so.1.0.2k
lrwxrwxrwx  1 root root      19 Aug  1 17:16 /lib64/libcrypto.so.1.1 -> libcrypto.so.1.1.1k
-rwxr-xr-x  1 root root 3090568 Jan 24  2024 /lib64/libcrypto.so.1.1.1k
[15:53:55] root@gxnt3 /data/PostgreSQL_16.3_V1/base/bin
➜ ls -l /lib64/libssl.so*
lrwxrwxrwx. 1 root root     16 Jul 16 10:56 /lib64/libssl.so -> libssl.so.1.0.2k
lrwxrwxrwx. 1 root root     16 Jul 16 10:56 /lib64/libssl.so.10 -> libssl.so.1.0.2k
-rwxr-xr-x. 1 root root 470328 Mar 21  2023 /lib64/libssl.so.1.0.2k
lrwxrwxrwx  1 root root     16 Aug  1 17:16 /lib64/libssl.so.1.1 -> libssl.so.1.1.1k
-rwxr-xr-x  1 root root 603592 Jan 24  2024 /lib64/libssl.so.1.1.1k


yum install -y tcpdump
tcpdump -i any -n port 9003