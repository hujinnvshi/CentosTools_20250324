# 安装依赖包 install python3
sudo yum install gcc* python3-devel git

# 系统安装 psutil
sudo pip3 install psutil

# 创建虚拟环境
mkdir /root/linux_netwatch
cd /root/linux_netwatch
python3 -m venv .p3venv

# 激活虚拟环境
source .p3venv/bin/activate

# 在虚拟环境中安装
pip install --upgrade pip
pip3 install psutil
pip install --upgrade pip