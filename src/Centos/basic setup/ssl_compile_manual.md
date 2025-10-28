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
ls -l /usr/lib64/libssl.so.10
ls -l /usr/lib64/libcrypto.so.10


# 永久设置（添加到 ~/.bashrc 或 /etc/profile）
echo 'export LD_LIBRARY_PATH=/usr/local/openssl1.0/lib:$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/openssl10.sh
source /etc/profile.d/openssl10.sh

# 检查 PostgreSQL 依赖
ldd ./base/bin/postgres | grep ssl