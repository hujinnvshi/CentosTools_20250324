-- 查询函数定义
SELECT text 
FROM all_source 
WHERE owner = 'XCJ_TEST' 
AND name = 'udf_test' 
AND type = 'FUNCTION' 
ORDER BY line;

-- 查询函数的基本信息
SELECT owner, object_name, status, created, last_ddl_time 
FROM all_objects 
WHERE owner = 'XCJ_TEST' 
AND object_name = 'udf_test' 
AND object_type = 'FUNCTION';

-- 查询编译错误信息
SELECT line, position, text, attribute 
FROM all_errors 
WHERE owner = 'XCJ_TEST' 
AND name = 'udf_test' 
AND type = 'FUNCTION' 
ORDER BY sequence;

-- 查询函数参数信息
SELECT argument_name, position, data_type, in_out 
FROM all_arguments 
WHERE owner = 'XCJ_TEST' 
AND object_name = 'udf_test' 
AND object_type = 'FUNCTION' 
ORDER BY position;