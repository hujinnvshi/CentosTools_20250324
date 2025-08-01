useradd pyuser
chown -R pyuser:pyuser /data/pypro_example

# 进入项目目录
cd /data/pypro_example

# 激活虚拟环境
source venv/bin/activate

# 验证Python版本
python --version  # 应显示3.12.x

# 安装包示例
pip install numpy pandas

# 退出环境
deactivate

# 版本更新
cd /data/pypro_example
pyenv install 3.12.1
pyenv local 3.12.1



# 创建新项目
export PyProjectName = "pypro_portrecord_$(date +%Y%m%d)"
mkdir -p /data/$PyProjectName
cd /data/$PyProjectName
pyenv local 3.12.0
python -m venv .venv
useradd $PyProjectName -d /data/$PyProjectName
chown -R $PyProjectName:$PyProjectName /data/$PyProjectName