
# windows 导出exsi vm(远程,OK,删除ISO)
D:\ovftool\ovftool.exe --noSSLVerify "vi://root:Secsmart#612@172.16.48.15/c76-172.16.48.58-kdcv2" "D:\c76-172.16.48.58-kdcv2.ovf"
D:\ovftool\ovftool.exe --noSSLVerify "vi://root:Secsmart#612@172.16.48.11/Ubuntu24.04.1-GitlabRunner-(172.16.48.112)" "D:\u.ovf"

# windows 导出workstation vm(本地,OK)
D:\ovftool\ovftool.exe "D:\C48O9I\C48O9I.vmx" "D:\c48o9i_exp"

# PowerShell 手动打包
cd D:\c48o9i_exp
tar -cvf D:\c48o9i_exp.ova *

# PowerShell导入exsi,先修正ovf,修改摘要(删除mf,编制ovf)
& "D:\ovftool\ovftool.exe" `
--name=c48_172.16.48.30_oracle10g `
--diskMode=thin `
--datastore=hpn1 `
--network="VM Network" `
--noSSLVerify `
--acceptAllEulas `
--lax `
"D:\c48o9i_exp\C48O9I\C48O9I.ovf" `
"vi://root:Secsmart#612@172.16.48.11/"

# 直接导入原始虚拟机(删除cd/usb后需要重新启动虚拟机一次,更新vmx,无效)
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
