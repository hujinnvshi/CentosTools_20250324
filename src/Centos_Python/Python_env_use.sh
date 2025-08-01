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
mkdir /data/new_project
cd /data/new_project
pyenv local 3.11.6
python -m venv .venv
useradd pyuser
chown -R pyuser:pyuser /data/pypro_example