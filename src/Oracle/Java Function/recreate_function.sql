-- 查询原始 DDL
SELECT DBMS_METADATA.GET_DDL('FUNCTION', 'udf_test', 'XCJ_TEST') AS ddl 
FROM dual;

-- 重构函数的基本模板
CREATE OR REPLACE FUNCTION XCJ_TEST.udf_test1 (
    keyid INT,  -- 输入参数
    text VARCHAR2  -- 输入参数
) 
    RETURN VARCHAR2  -- 返回类型（从 all_arguments 查询获得）
AS 
LANGUAGE JAVA 
NAME 'JavaTest.enc(int,java.lang.String) return java.lang.String'
/

-- 授权语句
GRANT EXECUTE ON XCJ_TEST.udf_test1 TO PUBLIC;