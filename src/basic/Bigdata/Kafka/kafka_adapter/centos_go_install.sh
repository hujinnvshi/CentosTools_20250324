# 下载最新版 Go（请替换为最新版本号）
wget wget https://mirrors.aliyun.com/golang/go1.21.0.linux-amd64.tar.gz

# 解压到 /usr/local
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz

# 设置环境变量
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
echo "export GOPATH=\$HOME/go" >> ~/.bashrc
source ~/.bashrc

# 验证安装
go version