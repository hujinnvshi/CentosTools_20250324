# 在 GRUB 菜单按 e 键后，在 linux 行末尾添加：
autoinstall ds=nocloud-net;s=http://your-server.com/autoinstall/ubuntu24.yaml


# 1. 在已安装的系统上安装 subiquity
sudo apt update
sudo apt install subiquity

# 2. 启动 Subiquity 的配置导出功能
sudo subiquity-debug --dry-run --machine-config=/path/to/output.yaml

# 3. 或者从现有系统导出配置
sudo subiquity-debug --output /path/to/autoinstall.yaml
