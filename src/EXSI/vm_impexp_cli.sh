
# windows 导出exsi vm
D:\ovftool\ovftool.exe --noSSLVerify "vi://root:Secsmart#612@192.168.20.36/app/oracle10g" "D:\oracle10g.ova"

# windows 导出workstation vm
D:\ovftool\ovftool.exe "D:\C48O9I\C48O9I.vmx" "D:\c48o9i_exp"

# PowerShell 手动打包
cd D:\c48o9i_exp
tar -cvf D:\c48o9i_exp.ova *

# PowerShell导入exsi,先修正ovf,修改摘要(删除mf)
& "D:\ovftool\ovftool.exe" `
--name=c48_172.16.48.167_oracle9i `
--diskMode=thin `
--datastore=hpn1 `
--network="VM Network" `
--noSSLVerify `
--acceptAllEulas `
--lax `
"D:\c48o9i_exp\C48O9I\C48O9I.ovf" `
"vi://root:Secsmart#612@172.16.48.11/"

# 直接导入原始虚拟机(删除cd/usb后需要重新启动虚拟机一次，更新vmx)
& "D:\ovftool\ovftool.exe" `
--name=c48_172.16.48.167_oracle9i `
--diskMode=thin `
--datastore=hpn1 `
--network="VM Network" `
--noSSLVerify `
--acceptAllEulas `
--lax `
"D:\C48O9I\C48O9I.vmx" `
"vi://root:Secsmart#612@172.16.48.11/"
