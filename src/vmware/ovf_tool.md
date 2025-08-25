# 导出虚拟机（Win OK）
D:\ovftool\ovftool.exe --noSSLVerify "vi://root:Secsmart#612@192.168.20.36/app/oracle10g" "D:\oracle10g.ova"

# 导入虚拟机（Win OK）
D:\ovftool\ovftool.exe --noSSLVerify "D:\oracle10g.ova" "vi://root:Secsmart#612@192.168.20.36/app/oracle10g"