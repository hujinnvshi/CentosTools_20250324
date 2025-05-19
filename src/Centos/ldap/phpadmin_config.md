$servers->newServer('ldap_pla');
$servers->setValue('server','name','LDAP Server');
$servers->setValue('server','host','ldap.node3.com');
$servers->setValue('server','port',389);
$servers->setValue('server','base',array('dc=node3,dc=com'));
$servers->setValue('login','auth_type','cookie');
$servers->setValue('login','bind_id','cn=admin,dc=node3,dc=com');
$servers->setValue('login','bind_pass','123456');
$servers->setValue('server','tls',false);

cd /var/www/html/phpldapadmin/config/
vim config.php