-- 显示更详细的错误堆栈
SELECT * FROM all_errors 
WHERE owner = 'XCJ_TEST' 
AND name = 'UDF_TEST1' 
AND type = 'FUNCTION' 
ORDER BY sequence;
