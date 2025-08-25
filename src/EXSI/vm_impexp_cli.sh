
# windows 导出exsi vm
D:\ovftool\ovftool.exe --noSSLVerify "vi://root:Secsmart#612@192.168.20.36/app/oracle10g" "D:\oracle10g.ova"

# windows 导出workstation vm
D:\ovftool\ovftool.exe "D:\C48O9I\C48O9I.vmx" "D:\c48o9i"

# PowerShell 手动打包
cd D:\c48o9i
tar -cvf D:\c48o9i.ova *

# 导入exsi
D:\ovftool\ovftool.exe `
--name=c48_172.16.48.167_oracle9i `
--datastore=datastore1 `
--network="VM Network" `
--acceptAllEulas `
"D:\c48o9i.ova" `
"vi://root:Secsmart#612@172.16.48.11/"