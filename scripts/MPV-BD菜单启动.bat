@echo off
chcp 65001 >nul
REM ================================================================
REM  mpv-omniphony — Blu-ray BD-J 菜单启动器（Windows，自带 JRE 版）
REM ================================================================
REM 双击或命令行执行：
REM    MPV-BD菜单启动.bat  "D:\蓝光\壮志凌云2.iso"
REM
REM 功能：
REM   * 预先设置 LIBBLURAY_CP -> 本目录下 share\libbluray\libbluray-j2se-1.5.1.jar
REM     （注意：libbluray 读取的是 LIBBLURAY_CP 变量名 —— libbluray bdj.c
REM     中用 getenv("LIBBLURAY_CP") 读取，写错名会找不到 jar；
REM     且必须指向「带版本号的 j2se jar」，指向无版本号的 libbluray.jar
REM     会让 libbluray 的 awt jar 名切片公式算出 NULL，最终仍报
REM     libbluray.jar=0，详见同目录 BD_J_运行说明.txt）
REM   * 本压缩包已自带 jlink JRE（share\libbluray\jre），优先指向它，
REM     用户无需自行安装 Java。
REM   * 自动附加 --disc-menu=yes --bluray-device= 两个 mpv 参数进入菜单模式。
REM ================================================================
setlocal
  set HERE=%~dp0
  if exist "%HERE%share\libbluray\libbluray-j2se-1.5.1.jar" (
    set LIBBLURAY_CP=%HERE%share\libbluray\libbluray-j2se-1.5.1.jar
  ) else (
    echo [mpv-omniphony BD-J] 警告: 未找到 share\libbluray\libbluray-j2se-1.5.1.jar
  )
  REM 优先使用压缩包内自带的 jlink JRE（bin\server\jvm.dll）
  if exist "%HERE%share\libbluray\jre\bin\server\jvm.dll" (
    set BLURAY_JVM_LIB_PATH=%HERE%share\libbluray\jre\bin\server\jvm.dll
  ) else (
    if not "%JAVA_HOME%"=="" (
      if exist "%JAVA_HOME%\bin\server\jvm.dll" (
        set BLURAY_JVM_LIB_PATH=%JAVA_HOME%\bin\server\jvm.dll
      ) else (
        echo [mpv-omniphony BD-J] 警告: JAVA_HOME=%JAVA_HOME% 下没有 bin\server\jvm.dll
      )
    ) else (
      echo [mpv-omniphony BD-J] 提示: 未找到自带 JRE 也没有 JAVA_HOME。
      echo   BD-J 蓝光菜单将无法加载（可能直接播放主片）。
    )
  )
  "%HERE%mpv.exe" --disc-menu=yes --bluray-device=%*
endlocal
