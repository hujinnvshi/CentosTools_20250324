yum install -y binutils elfutils-libelf elfutils-libelf-devel glibc glibc-common glibc-devel gcc gcc-c++ libaio libaio-devel libgcc libstdc++ libstdc++-devel make sysstat unixODBC unixODBC-devel libXp libXp-devel

# 安装7zip（如果尚未安装）
sudo apt-get install p7zip-full p7zip-rar

# 解压ISO文件
7z x database_10201_linux64.iso -ooracle_files

# 进入解压目录
cd oracle_files

# 注意centos7.3兼容性问题处理
vm.hugetlb_shm_group = 501 这个配置什么含义