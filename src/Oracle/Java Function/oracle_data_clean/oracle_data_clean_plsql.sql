-- Oracle数据库垃圾数据自动化清理框架 PL/SQL实现
-- 作者：AI助手
-- 创建日期：2024-03-24
-- 描述：本脚本实现Oracle数据库垃圾数据的自动化识别和清理功能

-- 创建日志表
CREATE TABLE cleanup_log (
    log_id          NUMBER PRIMARY KEY,
    operation_type  VARCHAR2(50),
    object_type     VARCHAR2(50),
    object_owner    VARCHAR2(30),
    object_name     VARCHAR2(128),
    operation_time  TIMESTAMP,
    status          VARCHAR2(10),
    error_message   VARCHAR2(4000),
    space_saved     NUMBER,
    performed_by    VARCHAR2(30)
);

-- 创建日志序列
CREATE SEQUENCE cleanup_log_seq START WITH 1 INCREMENT BY 1;

-- 创建配置表
CREATE TABLE cleanup_config (
    config_id       NUMBER PRIMARY KEY,
    config_name     VARCHAR2(50),
    config_value    VARCHAR2(4000),
    description     VARCHAR2(1000),
    last_updated    TIMESTAMP,
    updated_by      VARCHAR2(30)
);

-- 插入默认配置
INSERT INTO cleanup_config VALUES (1, 'TABLE_INACTIVE_MONTHS', '6', '表未被访问的月数阈值', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (2, 'TABLE_MIN_ROWS', '10', '表最小行数阈值', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (3, 'TEMP_TABLE_MONTHS', '3', '临时表存在的月数阈值', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (4, 'DATAFILE_FREE_PCT', '70', '数据文件空闲百分比阈值', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (5, 'TABLESPACE_FREE_PCT', '80', '表空间空闲百分比阈值', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (6, 'AUTO_CLEANUP_ENABLED', 'FALSE', '是否启用自动清理', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (7, 'BACKUP_BEFORE_CLEANUP', 'TRUE', '清理前是否备份', SYSTIMESTAMP, USER);
INSERT INTO cleanup_config VALUES (8, 'EXCLUDED_SCHEMAS', 'SYS,SYSTEM,OUTLN,DBSNMP,APPQOSSYS,CTXSYS', '排除的模式', SYSTIMESTAMP, USER);
COMMIT;

-- 创建清理候选表
CREATE TABLE cleanup_candidates (
    candidate_id    NUMBER PRIMARY KEY,
    object_type     VARCHAR2(50),
    object_owner    VARCHAR2(30),
    object_name     VARCHAR2(128),
    reason          VARCHAR2(1000),
    identified_time TIMESTAMP,
    status          VARCHAR2(20) DEFAULT 'PENDING',
    approved_by     VARCHAR2(30),
    approved_time   TIMESTAMP,
    cleanup_time    TIMESTAMP,
    priority        NUMBER(1)
);

-- 创建候选序列
CREATE SEQUENCE cleanup_candidates_seq START WITH 1 INCREMENT BY 1;

-- 创建数据库清理包
CREATE OR REPLACE PACKAGE db_cleanup AS
    -- 常量定义
    c_version CONSTANT VARCHAR2(10) := '1.0.0';
    
    -- 公共类型定义
    TYPE object_rec IS RECORD (
        owner       VARCHAR2(30),
        object_name VARCHAR2(128),
        object_type VARCHAR2(50),
        reason      VARCHAR2(1000)
    );
    
    TYPE object_list IS TABLE OF object_rec;
    
    -- 公共函数和过程
    FUNCTION get_config_value(p_config_name IN VARCHAR2) RETURN VARCHAR2;
    PROCEDURE set_config_value(p_config_name IN VARCHAR2, p_config_value IN VARCHAR2);
    
    -- 数据收集模块
    PROCEDURE collect_statistics;
    FUNCTION identify_unused_tables RETURN object_list;
    FUNCTION identify_empty_tables RETURN object_list;
    FUNCTION identify_temp_tables RETURN object_list;
    FUNCTION identify_unused_datafiles RETURN object_list;
    FUNCTION identify_empty_tablespaces RETURN object_list;
    
    -- 分析决策模块
    PROCEDURE analyze_and_identify;
    PROCEDURE approve_candidate(p_candidate_id IN NUMBER, p_approved_by IN VARCHAR2);
    PROCEDURE reject_candidate(p_candidate_id IN NUMBER, p_rejected_by IN VARCHAR2);
    
    -- 执行清理模块
    PROCEDURE cleanup_approved_candidates;
    PROCEDURE cleanup_table(p_owner IN VARCHAR2, p_table_name IN VARCHAR2);
    PROCEDURE cleanup_datafile(p_file_name IN VARCHAR2);
    PROCEDURE cleanup_tablespace(p_tablespace_name IN VARCHAR2);
    
    -- 报告模块
    PROCEDURE generate_cleanup_report(p_days_back IN NUMBER DEFAULT 30);
    FUNCTION get_space_savings RETURN NUMBER;
    
    -- 主控过程
    PROCEDURE run_cleanup_cycle(p_auto_approve IN BOOLEAN DEFAULT FALSE);
END db_cleanup;
/

-- 创建数据库清理包体
CREATE OR REPLACE PACKAGE BODY db_cleanup AS
    -- 私有过程和函数
    PROCEDURE log_operation(
        p_operation_type IN VARCHAR2,
        p_object_type    IN VARCHAR2,
        p_object_owner   IN VARCHAR2,
        p_object_name    IN VARCHAR2,
        p_status         IN VARCHAR2,
        p_error_message  IN VARCHAR2 DEFAULT NULL,
        p_space_saved    IN NUMBER DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO cleanup_log (
            log_id, operation_type, object_type, object_owner, object_name,
            operation_time, status, error_message, space_saved, performed_by
        ) VALUES (
            cleanup_log_seq.NEXTVAL, p_operation_type, p_object_type, p_object_owner, p_object_name,
            SYSTIMESTAMP, p_status, p_error_message, p_space_saved, USER
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error logging operation: ' || SQLERRM);
    END log_operation;
    
    -- 获取配置值
    FUNCTION get_config_value(p_config_name IN VARCHAR2) RETURN VARCHAR2 IS
        v_value VARCHAR2(4000);
    BEGIN
        SELECT config_value INTO v_value
        FROM cleanup_config
        WHERE config_name = p_config_name;
        
        RETURN v_value;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END get_config_value;
    
    -- 设置配置值
    PROCEDURE set_config_value(p_config_name IN VARCHAR2, p_config_value IN VARCHAR2) IS
    BEGIN
        UPDATE cleanup_config
        SET config_value = p_config_value,
            last_updated = SYSTIMESTAMP,
            updated_by = USER
        WHERE config_name = p_config_name;
        
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO cleanup_config (
                config_id, config_name, config_value, description, last_updated, updated_by
            ) VALUES (
                (SELECT NVL(MAX(config_id), 0) + 1 FROM cleanup_config),
                p_config_name, p_config_value, 'Added by ' || USER, SYSTIMESTAMP, USER
            );
        END IF;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END set_config_value;
    
    -- 收集统计信息
    PROCEDURE collect_statistics IS
        v_excluded_schemas VARCHAR2(4000);
    BEGIN
        v_excluded_schemas := get_config_value('EXCLUDED_SCHEMAS');
        
        -- 记录操作开始
        log_operation('COLLECT_STATS', 'DATABASE', NULL, NULL, 'STARTED');
        
        -- 为所有用户表收集统计信息
        FOR r IN (
            SELECT owner, table_name
            FROM dba_tables
            WHERE owner NOT IN (
                SELECT REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL)
                FROM dual
                CONNECT BY REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL) IS NOT NULL
            )
        ) LOOP
            BEGIN
                DBMS_STATS.GATHER_TABLE_STATS(
                    ownname => r.owner,
                    tabname => r.table_name,
                    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
                    cascade => TRUE
                );
            EXCEPTION
                WHEN OTHERS THEN
                    log_operation('COLLECT_STATS', 'TABLE', r.owner, r.table_name, 'FAILED', SQLERRM);
            END;
        END LOOP;
        
        -- 记录操作完成
        log_operation('COLLECT_STATS', 'DATABASE', NULL, NULL, 'COMPLETED');
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('COLLECT_STATS', 'DATABASE', NULL, NULL, 'FAILED', SQLERRM);
            RAISE;
    END collect_statistics;
    
    -- 识别长期未使用的表
    FUNCTION identify_unused_tables RETURN object_list IS
        v_result object_list := object_list();
        v_months NUMBER;
        v_excluded_schemas VARCHAR2(4000);
    BEGIN
        v_months := TO_NUMBER(get_config_value('TABLE_INACTIVE_MONTHS'));
        v_excluded_schemas := get_config_value('EXCLUDED_SCHEMAS');
        
        SELECT object_rec(owner, table_name, 'TABLE', 
               '表' || table_name || '已有' || ROUND(MONTHS_BETWEEN(SYSDATE, last_analyzed)) || '个月未被访问')
        BULK COLLECT INTO v_result
        FROM dba_tables
        WHERE owner NOT IN (
            SELECT REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL)
            FROM dual
            CONNECT BY REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL) IS NOT NULL
        )
        AND last_analyzed < ADD_MONTHS(SYSDATE, -v_months)
        AND table_name NOT LIKE 'BIN$%'; -- 排除回收站对象
        
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('IDENTIFY', 'UNUSED_TABLES', NULL, NULL, 'FAILED', SQLERRM);
            RETURN object_list();
    END identify_unused_tables;
    
    -- 识别空表或记录很少的表
    FUNCTION identify_empty_tables RETURN object_list IS
        v_result object_list := object_list();
        v_min_rows NUMBER;
        v_excluded_schemas VARCHAR2(4000);
    BEGIN
        v_min_rows := TO_NUMBER(get_config_value('TABLE_MIN_ROWS'));
        v_excluded_schemas := get_config_value('EXCLUDED_SCHEMAS');
        
        SELECT object_rec(owner, table_name, 'TABLE', 
               '表' || table_name || '只有' || num_rows || '行记录')
        BULK COLLECT INTO v_result
        FROM dba_tables
        WHERE owner NOT IN (
            SELECT REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL)
            FROM dual
            CONNECT BY REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL) IS NOT NULL
        )
        AND num_rows < v_min_rows
        AND num_rows > 0 -- 确保统计信息已收集
        AND last_analyzed > ADD_MONTHS(SYSDATE, -1) -- 确保统计信息较新
        AND table_name NOT LIKE 'BIN$%'; -- 排除回收站对象
        
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('IDENTIFY', 'EMPTY_TABLES', NULL, NULL, 'FAILED', SQLERRM);
            RETURN object_list();
    END identify_empty_tables;
    
    -- 识别临时表命名但长期存在的表
    FUNCTION identify_temp_tables RETURN object_list IS
        v_result object_list := object_list();
        v_months NUMBER;
        v_excluded_schemas VARCHAR2(4000);
    BEGIN
        v_months := TO_NUMBER(get_config_value('TEMP_TABLE_MONTHS'));
        v_excluded_schemas := get_config_value('EXCLUDED_SCHEMAS');
        
        SELECT object_rec(owner, object_name, 'TABLE', 
               '临时表' || object_name || '已存在' || ROUND(MONTHS_BETWEEN(SYSDATE, created)) || '个月')
        BULK COLLECT INTO v_result
        FROM dba_objects
        WHERE object_type = 'TABLE'
        AND owner NOT IN (
            SELECT REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL)
            FROM dual
            CONNECT BY REGEXP_SUBSTR(v_excluded_schemas, '[^,]+', 1, LEVEL) IS NOT NULL
        )
        AND (object_name LIKE '%TEMP%' OR object_name LIKE '%TMP%')
        AND created < ADD_MONTHS(SYSDATE, -v_months)
        AND object_name NOT LIKE 'BIN$%'; -- 排除回收站对象
        
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('IDENTIFY', 'TEMP_TABLES', NULL, NULL, 'FAILED', SQLERRM);
            RETURN object_list();
    END identify_temp_tables;
    
    -- 识别使用率低的数据文件
    FUNCTION identify_unused_datafiles RETURN object_list IS
        v_result object_list := object_list();
        v_pct NUMBER;
        v_excluded_schemas VARCHAR2(4000);
    BEGIN
        v_pct := TO_NUMBER(get_config_value('DATAFILE_FREE_PCT'));
        
        SELECT object_rec(NULL, df.file_name, 'DATAFILE', 
               '数据文件' || df.file_name || '空闲空间' || ROUND(fs.bytes/df.bytes * 100, 2) || '%')
        BULK COLLECT INTO v_result
        FROM dba_data_files df,
             (SELECT file_id, SUM(bytes) bytes
              FROM dba_free_space
              GROUP BY file_id) fs
        WHERE df.file_id = fs.file_id
        AND fs.bytes/df.bytes * 100 > v_pct
        AND df.tablespace_name NOT IN ('SYSTEM', 'SYSAUX', 'UNDO', 'TEMP');
        
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('IDENTIFY', 'UNUSED_DATAFILES', NULL, NULL, 'FAILED', SQLERRM);
            RETURN object_list();
    END identify_unused_datafiles;
    
    -- 识别空表空间或使用率低的表空间
    FUNCTION identify_empty_tablespaces RETURN object_list IS
        v_result object_list := object_list();
        v_pct NUMBER;
    BEGIN
        v_pct := TO_NUMBER(get_config_value('TABLESPACE_FREE_PCT'));
        
        -- 识别使用率低的表空间
        FOR r IN (
            SELECT a.tablespace_name,
                   ROUND(SUM(NVL(b.bytes,0))/SUM(a.bytes) * 100, 2) free_pct
            FROM dba_data_files a,
                 dba_free_space b
            WHERE a.file_id = b.file_id(+)
            AND a.tablespace_name NOT IN ('SYSTEM', 'SYSAUX', 'UNDO', 'TEMP')
            GROUP BY a.tablespace_name
            HAVING ROUND(SUM(NVL(b.bytes,0))/SUM(a.bytes) * 100, 2) > v_pct
        ) LOOP
            v_result.EXTEND;
            v_result(v_result.LAST) := object_rec(NULL, r.tablespace_name, 'TABLESPACE', 
                                                 '表空间' || r.tablespace_name || '空闲空间' || r.free_pct || '%');
        END LOOP;
        
        -- 识别不包含任何对象的表空间
        FOR r IN (
            SELECT a.tablespace_name
            FROM dba_tablespaces a
            WHERE a.contents = 'PERMANENT'
            AND a.tablespace_name NOT IN ('SYSTEM', 'SYSAUX')
            AND NOT EXISTS (
              SELECT 1 FROM dba_segments
              WHERE tablespace_name = a.tablespace_name
            )
        ) LOOP
            v_result.EXTEND;
            v_result(v_result.LAST) := object_rec(NULL, r.tablespace_name, 'TABLESPACE', 
                                                 '表空间' || r.tablespace_name || '不包含任何对象');
        END LOOP;
        
        RETURN v_result;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('IDENTIFY', 'EMPTY_TABLESPACES', NULL, NULL, 'FAILED', SQLERRM);
            RETURN object_list();
    END identify_empty_tablespaces;
    
    -- 分析并识别垃圾数据
    PROCEDURE analyze_and_identify IS
        v_unused_tables object_list;
        v_empty_tables object_list;
        v_temp_tables object_list;
        v_unused_datafiles object_list;
        v_empty_tablespaces object_list;
    BEGIN
        -- 记录操作开始
        log_operation('ANALYZE', 'DATABASE', NULL, NULL, 'STARTED');
        
        -- 识别各类垃圾数据
        v_unused_tables := identify_unused_tables();
        v_empty_tables := identify_empty_tables();
        v_temp_tables := identify_temp_tables();
        v_unused_datafiles := identify_unused_datafiles();
        v_empty_tablespaces := identify_empty_tablespaces();
        
        -- 将识别结果添加到候选表
        -- 1. 未使用的表
        FOR i IN 1..v_unused_tables.COUNT LOOP
            INSERT INTO cleanup_candidates (
                candidate_id, object_type, object_owner, object_name, 
                reason, identified_time, status, priority
            ) VALUES (
                cleanup_candidates_seq.NEXTVAL, v_unused_tables(i).object_type,
                v_unused_tables(i).owner, v_unused_tables(i).object_name,
                v_unused_tables(i).reason, SYSTIMESTAMP, 'PENDING', 3
            );
        END LOOP;
        
        -- 2. 空表
        FOR i IN 1..v_empty_tables.COUNT LOOP
            INSERT INTO cleanup_candidates (
                candidate_id, object_type, object_owner, object_name, 
                reason, identified_time, status, priority
            ) VALUES (
                cleanup_candidates_seq.NEXTVAL, v_empty_tables(i).object_type,
                v_empty_tables(i).owner, v_empty_tables(i).object_name,
                v_empty_tables(i).reason, SYSTIMESTAMP, 'PENDING', 2
            );
        END LOOP;
        
        -- 3. 临时表
        FOR i IN 1..v_temp_tables.COUNT LOOP
            INSERT INTO cleanup_candidates (
                candidate_id, object_type, object_owner, object_name, 
                reason, identified_time, status, priority
            ) VALUES (
                cleanup_candidates_seq.NEXTVAL, v_temp_tables(i).object_type,
                v_temp_tables(i).owner, v_temp_tables(i).object_name,
                v_temp_tables(i).reason, SYSTIMESTAMP, 'PENDING', 1
            );
        END LOOP;
        
        -- 4. 未使用的数据文件
        FOR i IN 1..v_unused_datafiles.COUNT LOOP
            INSERT INTO cleanup_candidates (
                candidate_id, object_type, object_owner, object_name, 
                reason, identified_time, status, priority
            ) VALUES (
                cleanup_candidates_seq.NEXTVAL, v_unused_datafiles(i).object_type,
                v_unused_datafiles(i).owner, v_unused_datafiles(i).object_name,
                v_unused_datafiles(i).reason, SYSTIMESTAMP, 'PENDING', 4
            );
        END LOOP;
        
        -- 5. 空表空间
        FOR i IN 1..v_empty_tablespaces.COUNT LOOP
            INSERT INTO cleanup_candidates (
                candidate_id, object_type, object_owner, object_name, 
                reason, identified_time, status, priority
            ) VALUES (
                cleanup_candidates_seq.NEXTVAL, v_empty_tablespaces(i).object_type,
                v_empty_tablespaces(i).owner, v_empty_tablespaces(i).object_name,
                v_empty_tablespaces(i).reason, SYSTIMESTAMP, 'PENDING', 5
            );
        END LOOP;
        
        COMMIT;
        
        -- 记录操作完成
        log_operation('ANALYZE', 'DATABASE', NULL, NULL, 'COMPLETED');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            log_operation('ANALYZE', 'DATABASE', NULL, NULL, 'FAILED', SQLERRM);
            RAISE;
    END analyze_and_identify;
    
    -- 批准清理候选
    PROCEDURE approve_candidate(p_candidate_id IN NUMBER, p_approved_by IN VARCHAR2) IS
    BEGIN
        UPDATE cleanup_candidates
        SET status = 'APPROVED',
            approved_by = p_approved_by,
            approved_time = SYSTIMESTAMP
        WHERE candidate_id = p_candidate_id
        AND status = 'PENDING';
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, '找不到指定的候选ID或状态不是PENDING');
        END IF;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END approve_candidate;
    
    -- 拒绝清理候选
    PROCEDURE reject_candidate(p_candidate_id IN NUMBER, p_rejected_by IN VARCHAR2) IS
    BEGIN
        UPDATE cleanup_candidates
        SET status = 'REJECTED',
            approved_by = p_rejected_by,
            approved_time = SYSTIMESTAMP
        WHERE candidate_id = p_candidate_id
        AND status = 'PENDING';
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, '找不到指定的候选ID或状态不是PENDING');
        END IF;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END reject_candidate;
    
    -- 清理表
    PROCEDURE cleanup_table(p_owner IN VARCHAR2, p_table_name IN VARCHAR2) IS
        v_backup_enabled VARCHAR2(10);
        v_space_before NUMBER;
        v_space_after NUMBER;
        v_space_saved NUMBER;
    BEGIN
        -- 检查是否需要备份
        v_backup_enabled := get_config_value('BACKUP_BEFORE_CLEANUP');
        
        -- 获取表大小
        SELECT NVL(SUM(bytes), 0) INTO v_space_before
        FROM dba_segments
        WHERE owner = p_owner
        AND segment_name = p_table_name
        AND segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION');
        
        -- 如果需要备份，创建表备份
        IF v_backup_enabled = 'TRUE' THEN
            EXECUTE IMMEDIATE 'CREATE TABLE ' || p_owner || '.BKP_' || p_table_name || '_' || 
                              TO_CHAR(SYSDATE, 'YYYYMMDD') || ' AS SELECT * FROM ' || 
                              p_owner || '.' || p_table_name;
            
            log_operation('BACKUP', 'TABLE', p_owner, p_table_name, 'COMPLETED');
        END IF;
        
        -- 删除表
        EXECUTE IMMEDIATE 'DROP TABLE ' || p_owner || '.' || p_table_name;
        
        -- 计算节省的空间
        v_space_saved := v_space_before;
        
        -- 记录清理操作
        log_operation('CLEANUP', 'TABLE', p_owner, p_table_name, 'COMPLETED', NULL, v_space_saved);
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('CLEANUP', 'TABLE', p_owner, p_table_name, 'FAILED', SQLERRM);
            RAISE;
    END cleanup_table;
    
    -- 清理数据文件
    PROCEDURE cleanup_datafile(p_file_name IN VARCHAR2) IS
        v_tablespace_name VARCHAR2(30);
        v_space_before NUMBER;
    BEGIN
        -- 获取数据文件所属的表空间
        SELECT tablespace_name, bytes INTO v_tablespace_name, v_space_before
        FROM dba_data_files
        WHERE file_name = p_file_name;
        
        -- 尝试将数据文件脱机并删除
        BEGIN
            EXECUTE IMMEDIATE 'ALTER DATABASE DATAFILE ''' || p_file_name || ''' OFFLINE DROP';
            log_operation('CLEANUP', 'DATAFILE', NULL, p_file_name, 'COMPLETED', NULL, v_space_before);
        EXCEPTION
            WHEN OTHERS THEN
                -- 如果无法直接删除，尝试收缩数据文件
                BEGIN
                    EXECUTE IMMEDIATE 'ALTER DATABASE DATAFILE ''' || p_file_name || 
                                      ''' RESIZE 1M';
                    
                    -- 获取收缩后的大小
                    DECLARE
                        v_space_after NUMBER;
                    BEGIN
                        SELECT bytes INTO v_space_after
                        FROM dba_data_files
                        WHERE file_name = p_file_name;
                        
                        log_operation('RESIZE', 'DATAFILE', NULL, p_file_name, 'COMPLETED', 
                                     NULL, v_space_before - v_space_after);
                    END;
                EXCEPTION
                    WHEN OTHERS THEN
                        log_operation('CLEANUP', 'DATAFILE', NULL, p_file_name, 'FAILED', 
                                     '无法删除或收缩数据文件: ' || SQLERRM);
                        RAISE;
                END;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('CLEANUP', 'DATAFILE', NULL, p_file_name, 'FAILED', SQLERRM);
            RAISE;
    END cleanup_datafile;
    
    -- 清理表空间
    PROCEDURE cleanup_tablespace(p_tablespace_name IN VARCHAR2) IS
        v_space_before NUMBER;
        v_has_objects BOOLEAN := FALSE;
    BEGIN
        -- 检查表空间是否包含对象
        BEGIN
            SELECT 1 INTO v_space_before
            FROM dba_segments
            WHERE tablespace_name = p_tablespace_name
            AND ROWNUM = 1;
            
            v_has_objects := TRUE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_has_objects := FALSE;
        END;
        
        -- 获取表空间大小
        SELECT SUM(bytes) INTO v_space_before
        FROM dba_data_files
        WHERE tablespace_name = p_tablespace_name;
        
        -- 如果表空间不包含对象，直接删除
        IF NOT v_has_objects THEN
            EXECUTE IMMEDIATE 'DROP TABLESPACE ' || p_tablespace_name || 
                              ' INCLUDING CONTENTS AND DATAFILES';
            
            log_operation('CLEANUP', 'TABLESPACE', NULL, p_tablespace_name, 'COMPLETED', 
                         NULL, v_space_before);
        ELSE
            -- 如果包含对象，记录无法删除
            log_operation('CLEANUP', 'TABLESPACE', NULL, p_tablespace_name, 'SKIPPED', 
                         '表空间包含对象，无法删除');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_operation('CLEANUP', 'TABLESPACE', NULL, p_tablespace_name, 'FAILED', SQLERRM);
            RAISE;
    END cleanup_tablespace;
    
    -- 清理已批准的候选
    PROCEDURE cleanup_approved_candidates IS
    BEGIN
        -- 记录操作开始
        log_operation('CLEANUP', 'CANDIDATES', NULL, NULL, 'STARTED');
        
        -- 处理已批准的表
        FOR r IN (
            SELECT object_owner, object_name
            FROM cleanup_candidates
            WHERE status = 'APPROVED'
            AND object_type = 'TABLE'
            ORDER BY priority
        ) LOOP
            BEGIN
                cleanup_table(r.object_owner, r.object_name);
                
                UPDATE cleanup_candidates
                SET status = 'CLEANED',
                    cleanup_time = SYSTIMESTAMP
                WHERE object_owner = r.object_owner
                AND object_name = r.object_name
                AND object_type = 'TABLE'
                AND status = 'APPROVED';
            EXCEPTION
                WHEN OTHERS THEN
                    -- 记录错误但继续处理其他候选
                    NULL;
            END;
        END LOOP;
        
        -- 处理已批准的数据文件
        FOR r IN (
            SELECT object_name
            FROM cleanup_candidates
            WHERE status = 'APPROVED'
            AND object_type = 'DATAFILE'
            ORDER BY priority
        ) LOOP
            BEGIN
                cleanup_datafile(r.object_name);
                
                UPDATE cleanup_candidates
                SET status = 'CLEANED',
                    cleanup_time = SYSTIMESTAMP
                WHERE object_name = r.object_name
                AND object_type = 'DATAFILE'
                AND status = 'APPROVED';
            EXCEPTION
                WHEN OTHERS THEN
                    -- 记录错误但继续处理其他候选
                    NULL;
            END;
        END LOOP;
        
        -- 处理已批准的表空间
        FOR r IN (
            SELECT object_name
            FROM cleanup_candidates
            WHERE status = 'APPROVED'
            AND object_type = 'TABLESPACE'
            ORDER BY priority
        ) LOOP
            BEGIN
                cleanup_tablespace(r.object_name);
                
                UPDATE cleanup_candidates
                SET status = 'CLEANED',
                    cleanup_time = SYSTIMESTAMP
                WHERE object_name = r.object_name
                AND object_type = 'TABLESPACE'
                AND status = 'APPROVED';
            EXCEPTION
                WHEN OTHERS THEN
                    -- 记录错误但继续处理其他候选
                    NULL;
            END;
        END LOOP;
        
        COMMIT;
        
        -- 记录操作完成
        log_operation('CLEANUP', 'CANDIDATES', NULL, NULL, 'COMPLETED');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            log_operation('CLEANUP', 'CANDIDATES', NULL, NULL, 'FAILED', SQLERRM);
            RAISE;
    END cleanup_approved_candidates;
    
    -- 生成清理报告
    PROCEDURE generate_cleanup_report(p_days_back IN NUMBER DEFAULT 30) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('========== Oracle数据库垃圾数据清理报告 ==========');
        DBMS_OUTPUT.PUT_LINE('报告生成时间: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE('报告周期: 最近' || p_days_back || '天');
        DBMS_OUTPUT.PUT_LINE('');
        
        -- 清理操作统计
        DBMS_OUTPUT.PUT_LINE('1. 清理操作统计');
        DBMS_OUTPUT.PUT_LINE('-------------------');
        FOR r IN (
            SELECT object_type, status, COUNT(*) count
            FROM cleanup_log
            WHERE operation_type = 'CLEANUP'
            AND operation_time > SYSDATE - p_days_back
            GROUP BY object_type, status
            ORDER BY object_type, status
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(r.object_type, 15) || ' | ' || 
                                RPAD(r.status, 10) || ' | ' || r.count);
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE('');
        
        -- 空间节省统计
        DBMS_OUTPUT.PUT_LINE('2. 空间节省统计');
        DBMS_OUTPUT.PUT_LINE('-------------------');
        FOR r IN (
            SELECT object_type, 
                   SUM(space_saved)/1024/1024 space_mb
            FROM cleanup_log
            WHERE operation_type IN ('CLEANUP', 'RESIZE')
            AND operation_time > SYSDATE - p_days_back
            AND space_saved IS NOT NULL
            GROUP BY object_type
            ORDER BY space_mb DESC
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(r.object_type, 15) || ' | ' || 
                                ROUND(r.space_mb, 2) || ' MB');
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('总节省空间: ' || 
                            ROUND(get_space_savings()/1024/1024, 2) || ' MB');
        
        DBMS_OUTPUT.PUT_LINE('');
        
        -- 最近清理的对象
        DBMS_OUTPUT.PUT_LINE('3. 最近清理的对象 (最多显示10个)');
        DBMS_OUTPUT.PUT_LINE('-------------------');
        FOR r IN (
            SELECT object_type, object_owner, object_name, 
                   TO_CHAR(operation_time, 'YYYY-MM-DD HH24:MI:SS') cleanup_time,
                   ROUND(space_saved/1024/1024, 2) space_mb
            FROM cleanup_log
            WHERE operation_type = 'CLEANUP'
            AND status = 'COMPLETED'
            AND operation_time > SYSDATE - p_days_back
            ORDER BY operation_time DESC
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(r.object_type, 12) || ' | ' || 
                                RPAD(NVL(r.object_owner, ' '), 12) || ' | ' ||
                                RPAD(r.object_name, 30) || ' | ' ||
                                r.cleanup_time || ' | ' ||
                                NVL(TO_CHAR(r.space_mb) || ' MB', 'N/A'));
            
            -- 只显示前10个
            IF ROWNUM >= 10 THEN
                EXIT;
            END IF;
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE('');
        
        -- 待清理候选
        DBMS_OUTPUT.PUT_LINE('4. 待清理候选 (状态为PENDING)');
        DBMS_OUTPUT.PUT_LINE('-------------------');
        FOR r IN (
            SELECT object_type, object_owner, object_name, reason,
                   TO_CHAR(identified_time, 'YYYY-MM-DD HH24:MI:SS') identified_time
            FROM cleanup_candidates
            WHERE status = 'PENDING'
            ORDER BY priority, identified_time
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(r.object_type, 12) || ' | ' || 
                                RPAD(NVL(r.object_owner, ' '), 12) || ' | ' ||
                                RPAD(r.object_name, 30) || ' | ' ||
                                r.identified_time);
            DBMS_OUTPUT.PUT_LINE('   原因: ' || r.reason);
            DBMS_OUTPUT.PUT_LINE('-------------------');
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('========== 报告结束 ==========');
    END generate_cleanup_report;
    
    -- 获取节省的空间
    FUNCTION get_space_savings RETURN NUMBER IS
        v_total_saved NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(space_saved), 0) INTO v_total_saved
        FROM cleanup_log
        WHERE operation_type IN ('CLEANUP', 'RESIZE')
        AND space_saved IS NOT NULL;
        
        RETURN v_total_saved;
    END get_space_savings;
    
    -- 主控过程
    PROCEDURE run_cleanup_cycle(p_auto_approve IN BOOLEAN DEFAULT FALSE) IS
        v_auto_cleanup VARCHAR2(10);
    BEGIN
        -- 检查是否启用自动清理
        v_auto_cleanup := get_config_value('AUTO_CLEANUP_ENABLED');
        
        -- 收集统计信息
        collect_statistics;
        
        -- 分析并识别垃圾数据
        analyze_and_identify;
        
        -- 如果启用了自动清理或传入了自动批准参数
        IF v_auto_cleanup = 'TRUE' OR p_auto_approve THEN
            -- 自动批准所有候选
            FOR r IN (
                SELECT candidate_id
                FROM cleanup_candidates
                WHERE status = 'PENDING'
            ) LOOP
                approve_candidate(r.candidate_id, 'AUTO_APPROVED');
            END LOOP;
            
            -- 执行清理
            cleanup_approved_candidates;
        END IF;
        
        -- 生成报告
        generate_cleanup_report;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            log_operation('RUN_CYCLE', 'DATABASE', NULL, NULL, 'FAILED', SQLERRM);
            RAISE;
    END run_cleanup_cycle;
    
END db_cleanup;
/

-- 创建调度作业
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'DB_CLEANUP_JOB',
        job_type        => 'STORED_PROCEDURE',
        job_action      => 'db_cleanup.run_cleanup_cycle',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=WEEKLY; BYDAY=SUN; BYHOUR=2; BYMINUTE=0; BYSECOND=0',
        enabled         => FALSE,
        comments        => 'Oracle数据库垃圾数据自动清理作业'
    );
END;
/

-- 创建用于手动运行清理的存储过程
CREATE OR REPLACE PROCEDURE run_db_cleanup(
    p_auto_approve IN VARCHAR2 DEFAULT 'N'
) AS
BEGIN
    IF UPPER(p_auto_approve) = 'Y' THEN
        db_cleanup.run_cleanup_cycle(TRUE);
    ELSE
        db_cleanup.run_cleanup_cycle(FALSE);
    END IF;
END;
/

-- 创建用于查看清理报告的存储过程
CREATE OR REPLACE PROCEDURE show_cleanup_report(
    p_days_back IN NUMBER DEFAULT 30
) AS
BEGIN
    db_cleanup.generate_cleanup_report(p_days_back);
END;
/

-- 创建用于批准清理候选的存储过程
CREATE OR REPLACE PROCEDURE approve_cleanup_candidate(
    p_candidate_id IN NUMBER
) AS
BEGIN
    db_cleanup.approve_candidate(p_candidate_id, USER);
    DBMS_OUTPUT.PUT_LINE('候选ID ' || p_candidate_id || ' 已批准清理');
END;
/

-- 创建用于拒绝清理候选的存储过程
CREATE OR REPLACE PROCEDURE reject_cleanup_candidate(
    p_candidate_id IN NUMBER
) AS
BEGIN
    db_cleanup.reject_candidate(p_candidate_id, USER);
    DBMS_OUTPUT.PUT_LINE('候选ID ' || p_candidate_id || ' 已拒绝清理');
END;
/

-- 创建用于执行已批准清理的存储过程
CREATE OR REPLACE PROCEDURE execute_approved_cleanup AS
BEGIN
    db_cleanup.cleanup_approved_candidates;
    DBMS_OUTPUT.PUT_LINE('已执行所有批准的清理操作');
END;
/

-- 创建用于查看清理候选的存储过程
CREATE OR REPLACE PROCEDURE show_cleanup_candidates AS
BEGIN
    FOR r IN (
        SELECT candidate_id, object_type, object_owner, object_name, 
               reason, status, identified_time
        FROM cleanup_candidates
        WHERE status = 'PENDING'
        ORDER BY priority, identified_time
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('ID: ' || r.candidate_id);
        DBMS_OUTPUT.PUT_LINE('类型: ' || r.object_type);
        DBMS_OUTPUT.PUT_LINE('所有者: ' || NVL(r.object_owner, 'N/A'));
        DBMS_OUTPUT.PUT_LINE('名称: ' || r.object_name);
        DBMS_OUTPUT.PUT_LINE('原因: ' || r.reason);
        DBMS_OUTPUT.PUT_LINE('识别时间: ' || TO_CHAR(r.identified_time, 'YYYY-MM-DD HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE('-------------------');
    END LOOP;
END;
/

-- 使用说明
PROMPT
PROMPT Oracle数据库垃圾数据自动化清理框架已安装完成
PROMPT
PROMPT 可用的存储过程:
PROMPT 1. run_db_cleanup(p_auto_approve) - 运行完整的清理周期
PROMPT 2. show_cleanup_report(p_days_back) - 显示清理报告
PROMPT 3. show_cleanup_candidates - 显示待清理的候选
PROMPT 4. approve_cleanup_candidate(p_candidate_id) - 批准清理候选
PROMPT 5. reject_cleanup_candidate(p_candidate_id) - 拒绝清理候选
PROMPT 6. execute_approved_cleanup - 执行已批准的清理操作
PROMPT
PROMPT 示例:
PROMPT EXEC run_db_cleanup('N'); -- 运行清理周期但不自动批准
PROMPT EXEC show_cleanup_candidates; -- 查看待清理候选
PROMPT EXEC approve_cleanup_candidate(1); -- 批准ID为1的候选
PROMPT EXEC execute_approved_cleanup; -- 执行已批准的清理
PROMPT EXEC show_cleanup_report(30); -- 显示最近30天的清理报告
PROMPT