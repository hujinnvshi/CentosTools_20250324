https://hive.apache.org/docs/latest/language/languagemanual-types/#timestamps

CREATE TABLE IF NOT EXISTS events (

event_id INT COMMENT '事件 ID',

event_name STRING COMMENT '事件名称',

event_time TIMESTAMP WITH LOCAL TIME ZONE COMMENT '事件发生时间（带本地时区）',

location STRING COMMENT '事件地点'

)

COMMENT '包含带时区时间戳的事件表'

STORED AS ORC;

INSERT INTO events VALUES (

1,

'用户登录',

'2025-11-21 08:30:00', -- 假设此时间为北京时间（UTC+8）

'北京'

);
