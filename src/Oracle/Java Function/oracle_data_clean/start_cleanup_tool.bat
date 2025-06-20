@echo off
REM Oracle数据库垃圾数据清理工具启动脚本
REM 用于在Windows环境下启动Java应用程序

REM 设置环境变量
if "%JAVA_HOME%"=="" set JAVA_HOME=C:\Program Files\Java\jdk1.8.0_281
if "%ORACLE_HOME%"=="" set ORACLE_HOME=C:\app\oracle\product\19.0.0\dbhome_1
set CLASSPATH=.

REM 添加Oracle JDBC驱动到类路径
if exist "%ORACLE_HOME%\jdbc\lib" (
    for %%f in ("%ORACLE_HOME%\jdbc\lib\*.jar") do (
        set CLASSPATH=!CLASSPATH!;%%f
    )
)

REM 如果找不到Oracle JDBC驱动，尝试在当前目录查找
if not exist "%ORACLE_HOME%\jdbc\lib\ojdbc8.jar" (
    if not exist "%ORACLE_HOME%\jdbc\lib\ojdbc7.jar" (
        if exist "ojdbc8.jar" (
            set CLASSPATH=%CLASSPATH%;ojdbc8.jar
        ) else if exist "ojdbc7.jar" (
            set CLASSPATH=%CLASSPATH%;ojdbc7.jar
        ) else (
            echo 警告: 找不到Oracle JDBC驱动。请确保ojdbc7.jar或ojdbc8.jar在当前目录或Oracle安装目录中。
            echo 您可以从Oracle官网下载JDBC驱动: https://www.oracle.com/database/technologies/jdbc-drivers-12c-downloads.html
        )
    )
)

REM 编译Java程序
echo 编译Java程序...
"%JAVA_HOME%\bin\javac" -cp "%CLASSPATH%" OracleDataCleanup.java

if %ERRORLEVEL% neq 0 (
    echo 编译失败，请检查Java环境和代码。
    pause
    exit /b 1
)

REM 运行Java程序
echo 启动Oracle数据库垃圾数据清理工具...
"%JAVA_HOME%\bin\java" -cp "%CLASSPATH%" oracle.data.cleanup.OracleDataCleanup

pause