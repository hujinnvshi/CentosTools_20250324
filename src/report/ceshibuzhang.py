import pandas as pd
import pymysql
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from datetime import datetime, timedelta
import os
import warnings
from typing import List, Tuple, Optional

# 禁用pandas的警告
warnings.filterwarnings('ignore', category=UserWarning)

# ================ 配置部分 ================
DB_CONFIG = {
    'host': '172.16.49.24',
    'port': 3306,
    'user': 'root',
    'password': '123456',
    'database': 'zentao',
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}

EMAIL_CONFIG = {
    'smtp_server': 'smtp.exmail.qq.com',
    'smtp_port': 587,
    'username': 'zhangning@secsmart.net',
    'password': '7qnR9sqB9LTtYM9P',
    'from_addr': 'zhangning@secsmart.net',
    'to_addrs': ['zhangning@secsmart.net','zhangning@secsmart.net'],
    'cc_addrs': ['zhangning@secsmart.net','zhangning@secsmart.net'],
    'ssl': False,
    'starttls': True
}

# ================ 核心函数 ================
def get_current_week_dates() -> Tuple[str, str]:
    """获取当前周的日期范围（上周五12:01到本周五12:00）"""
    today = datetime.now()
    monday = today - timedelta(days=today.weekday())
    start_date = (monday - timedelta(days=3)).strftime('%Y-%m-%d 12:01:00')
    end_date = (monday + timedelta(days=4)).strftime('%Y-%m-%d 12:00:00')
    return start_date, end_date

def test_db_connection() -> bool:
    """测试数据库连接是否正常"""
    try:
        conn = pymysql.connect(**DB_CONFIG)
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
            conn.close()
        return True
    except Exception as e:
        print(f"🔴 数据库连接测试失败: {str(e)}")
        print(f"请检查以下配置：")
        print(f"- 主机: {DB_CONFIG['host']}")
        print(f"- 端口: {DB_CONFIG['port']}")
        print(f"- 用户: {DB_CONFIG['user']}")
        print(f"- 数据库: {DB_CONFIG['database']}")
        return False

def execute_sql_query(conn, sql: str) -> Optional[pd.DataFrame]:
    """执行SQL查询并返回DataFrame"""
    try:
        df = pd.read_sql(sql, conn)
        if not df.empty:
            print(f"✅ 查询到 {len(df)} 条记录")
            print("样例数据预览:")
            print(df.iloc[0].to_dict())  # 打印第一条记录
        return df
    except Exception as e:
        print(f"🔴 SQL执行错误: {str(e)}")
        return None

def query_bug_data(start_date: str, end_date: str) -> Optional[pd.DataFrame]:
    """查询禅道Bug数据"""
    sql = f"""
    -- 第一部分：正常导入的Bug
    SELECT 
        b.id AS bug_id,
        u1.realname AS creator,
        pj.name AS project,
        pd.name AS product,
        dz.标准产品名称 AS standard_product,
        dz.所属开发部 AS dev_team,
        CASE WHEN LOCATE('【B8】', pj.name) > 0 THEN 'YES' ELSE 'NO' END AS is_b8_project,
        b.openedDate AS created_time,
        b.resolvedDate AS resolved_time,
        b.lastEditedDate AS last_updated,
        b.severity AS severity_level,
        CASE b.severity 
            WHEN 1 THEN 5 
            WHEN 2 THEN 3 
            WHEN 3 THEN 1 
            WHEN 4 THEN 0.5 
        END AS di_score,
        la.value AS resolution,
        b.title AS title,
        COALESCE(b.resolvedBy, b.assignedTo) AS resolver,
        b.type AS bug_type,
        b.activatedCount AS activation_count,
        b.activatedDate AS last_activated
    FROM zt_bug b
    LEFT JOIN zt_product pd ON b.product = pd.id
    LEFT JOIN 禅道产品信息 dz ON dz.禅道所属产品 = pd.name
    LEFT JOIN zt_project pj ON b.project = pj.id
    LEFT JOIN zt_user u1 ON u1.account = b.openedBy
    LEFT JOIN zt_lang la ON b.resolution = la.key AND la.section = 'resolutionList'
    WHERE b.type = 'import'
      AND la.value <> '非问题'
      AND b.id NOT IN (25507, 25808)
      AND b.lastEditedDate BETWEEN '{start_date}' AND '{end_date}'
    
    UNION ALL
    
    -- 第二部分：被激活过的Bug
    SELECT 
        b.id AS bug_id,
        u1.realname AS creator,
        pj.name AS project,
        pd.name AS product,
        dz.标准产品名称 AS standard_product,
        dz.所属开发部 AS dev_team,
        CASE WHEN LOCATE('【B8】', pj.name) > 0 THEN 'YES' ELSE 'NO' END AS is_b8_project,
        b.openedDate AS created_time,
        b.resolvedDate AS resolved_time,
        b.activatedDate AS last_updated,
        b.severity AS severity_level,
        CASE b.severity 
            WHEN 1 THEN 5 
            WHEN 2 THEN 3 
            WHEN 3 THEN 1 
            WHEN 4 THEN 0.5 
        END AS di_score,
        la.value AS resolution,
        b.title AS title,
        COALESCE(b.resolvedBy, b.assignedTo) AS resolver,
        b.type AS bug_type,
        b.activatedCount AS activation_count,
        b.activatedDate AS last_activated
    FROM zt_bug b
    LEFT JOIN zt_product pd ON b.product = pd.id
    LEFT JOIN 禅道产品信息 dz ON dz.禅道所属产品 = pd.name
    LEFT JOIN zt_project pj ON b.project = pj.id
    LEFT JOIN zt_user u1 ON u1.account = b.openedBy
    LEFT JOIN zt_lang la ON b.resolution = la.key AND la.section = 'resolutionList'
    WHERE b.activatedCount > 0
      AND la.value <> '非问题'
      AND b.id NOT IN (25507, 25808)
      AND b.activatedDate BETWEEN '{start_date}' AND '{end_date}'
    """
    
    try:
        with pymysql.connect(**DB_CONFIG) as conn:
            return execute_sql_query(conn, sql)
    except Exception as e:
        print(f"🔴 数据库操作异常: {str(e)}")
        return None

def save_to_excel(df: pd.DataFrame, filename: str) -> str:
    """将数据保存为Excel文件"""
    try:
        os.makedirs('reports', exist_ok=True)
        filepath = os.path.join('reports', filename)
        
        with pd.ExcelWriter(filepath, engine='xlsxwriter') as writer:
            df.to_excel(writer, index=False, sheet_name='Bug报告')
            
            workbook = writer.book
            worksheet = writer.sheets['Bug报告']
            
            # 设置自适应列宽
            for i, col in enumerate(df.columns):
                max_len = max(
                    df[col].astype(str).str.len().max(),
                    len(str(col))
                ) + 2
                worksheet.set_column(i, i, min(max_len, 50))
            
            # 设置表头样式
            header_format = workbook.add_format({
                'bold': True,
                'text_wrap': True,
                'valign': 'top',
                'fg_color': '#D7E4BC',
                'border': 1
            })
            worksheet.set_row(0, None, header_format)
        
        print(f"💾 Excel文件已保存: {filepath}")
        return filepath
    except Exception as e:
        print(f"🔴 保存Excel失败: {str(e)}")
        raise

def send_email(filepath: str, start_date: str, end_date: str) -> bool:
    """发送带附件的邮件"""
    try:
        # 创建邮件
        msg = MIMEMultipart()
        msg['From'] = EMAIL_CONFIG['from_addr']
        msg['To'] = ', '.join(EMAIL_CONFIG['to_addrs'])
        msg['Cc'] = ', '.join(EMAIL_CONFIG['cc_addrs'])
        msg['Subject'] = f"禅道Bug周报 ({start_date} 至 {end_date})"
        
        # 邮件正文
        body = f"""
        <html>
            <body style="font-family: Arial, sans-serif; line-height: 1.6;">
                <p>您好，</p>
                <p>附件是本周的禅道Bug报告，时间范围：<br>
                <strong>{start_date}</strong> 至 <strong>{end_date}</strong></p>
                
                <p>📅 生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                <hr style="border: 0.5px dashed #ccc; margin: 15px 0;">
                <p style="color: #666; font-size: 0.9em;">
                    此邮件为系统自动发送，请勿直接回复。<br>
                    如有问题请联系IT支持。
                </p>
            </body>
        </html>
        """
        msg.attach(MIMEText(body, 'html'))
        
        # 添加附件
        with open(filepath, 'rb') as f:
            part = MIMEApplication(f.read(), Name=os.path.basename(filepath))
        part['Content-Disposition'] = f'attachment; filename="{os.path.basename(filepath)}"'
        msg.attach(part)
        
        # 发送邮件
        with smtplib.SMTP(EMAIL_CONFIG['smtp_server'], EMAIL_CONFIG['smtp_port']) as server:
            if EMAIL_CONFIG.get('starttls', False):
                server.starttls()
            
            server.login(EMAIL_CONFIG['username'], EMAIL_CONFIG['password'])
            recipients = EMAIL_CONFIG['to_addrs'] + EMAIL_CONFIG['cc_addrs']
            server.sendmail(EMAIL_CONFIG['from_addr'], recipients, msg.as_string())
        
        print("📧 邮件发送成功！")
        return True
    except Exception as e:
        print(f"🔴 邮件发送失败: {str(e)}")
        return False

# ================ 主程序 ================
def main():
    print("="*50)
    print("🛠️ 禅道Bug周报生成系统")
    print(f"🕒 启动时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*50)
    
    # 1. 检查数据库连接
    if not test_db_connection():
        return
    
    # 2. 获取日期范围
    start_date, end_date = get_current_week_dates()
    print(f"\n📅 报告周期: {start_date} 至 {end_date}")
    
    # 3. 查询数据
    print("\n🔍 正在查询数据...")
    df = query_bug_data(start_date, end_date)
    
    if df is None or df.empty:
        print("\n⚠️ 没有查询到有效数据，程序终止")
        print("可能原因：")
        print("- 指定日期范围内无符合条件的数据")
        print("- 数据库表结构发生变化")
        print("- SQL查询条件需要调整")
        return
    
    # 4. 保存Excel
    print("\n💾 正在生成Excel文件...")
    filename = f"禅道Bug周报_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    try:
        excel_path = save_to_excel(df, filename)
    except Exception as e:
        print(f"🔴 无法生成Excel文件: {str(e)}")
        return
    
    # 5. 发送邮件
    print("\n📧 正在发送邮件...")
    if not send_email(excel_path, start_date, end_date):
        return
    
    # 6. 清理临时文件
    try:
        os.remove(excel_path)
        print(f"\n🧹 已清理临时文件: {excel_path}")
    except Exception as e:
        print(f"⚠️ 临时文件清理失败: {str(e)}")
    
    print("\n✅ 所有操作已完成！")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n🛑 程序被用户中断")
    except Exception as e:
        print(f"\n🔴 程序运行异常: {str(e)}")
    finally:
        print("\n🏁 程序结束")