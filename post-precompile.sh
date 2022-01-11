#!/bin/bash
#
#********************************************************************
#Author:                songliangcheng
#QQ:                    2192383945
#Date:                  2022-01-10
#FileName：             pre-compile.sh
#URL:                   http://blog.mykernel.cn
#Description：          对二进制目录完成后续操作
#Copyright (C):        2022 All rights reserved
#********************************************************************
set -eu


Usage() {
cat <<EOF
  $(basename $0) [-t] [-v] [-b] [-i] -f 解压的归档
        -p dir 应用目录, 满足app-release(.arch)? 格式
        -a 解压预编译包, 相当于-lbiv
        -v 自动链接不带版本号
        -b 自动将安装目录中的bin, 导出到path
        -i 自动导出头文件
        -l 自动库文件
        -s '<prog> [opt]' 自动生成systemd配置文件, 里面的命令是相对于应用展开的目录.
        -h help

  1.完成将应用目录后续的导出PATH, lib, include, 自动链接
  $(basename $0) -ap /opt/node_exporter-1.3.1.linux-amd64
  2. 完成1之外，额外支持添加systemd脚本
  $(basename $0) -ap /opt/node_exporter-1.3.1.linux-amd64 -a '<可执行程序> [opt]'
EOF
  exit -1
}


# 全局初始化
TARGET_DIR=""
VERSION=""
BIN=""
INCLUDE=""
SYSTEMD=""
LIB=""
APP_DIR=""

while getopts "t:f:as:p:lbvi" opt
do
   case $opt in
        p)
        #应用目录
        APP_DIR=${OPTARG}
        ;;
        v)
        #VERSION:是否将带有release号的目录, 链接到同组目录应用名
        VERSION=1
        ;;
        b)
        #BIN: 是否将解压目录中的bin, 写入PATH
        BIN=1
        ;;
        i)
        INCLUDE=1
        ;;
        l)
        LIB=1
        ;;
        s)
        SYSTEMD=1
        PROG=${OPTARG}
        ;;
        a)
        LIB=1
        INCLUDE=1
        BIN=1
        VERSION=1
        ;;
        ?)
        Usage
        ;;
   esac
done

############### 验证归档文件名合格
VERSION=${VERSION:-0}
BIN=${BIN:-0}
INCLUDE=${INCLUDE:-0}
LIB=${LIB:-0}
SYSTEMD=${SYSTEMD:-0}
function echof() {
        echo -e "\033[${3:-1};3${2:-1}m${1}\033[0m"
}

# 修正目录
if ! ( [ -n "$APP_DIR" ] && [[ $APP_DIR =~ [[:alpha:]]+-[0-9.]+.* ]] ); then
        echo "$APP_DIR, 不满足语义化版本, app-release(.arch)?"
        Usage
        exit -1
else
        echof "$APP_DIR 满足语义化版本" 2
fi

APP_PATH=$(readlink -f $APP_DIR)
APP_DIR=$(basename $APP_PATH)
TARGET_DIR=$(dirname $APP_PATH)

appname=$(echo $APP_DIR | grep -Eo '^[^-]+')
release=$(echo $APP_DIR | grep -Eo '[0-9]+.[0-9]+.[0-9]+')

# 链接
if [ -n $release ]; then
        if [ $VERSION -eq 1 ]; then
                echof "${TARGET_DIR}/$APP_DIR -> ${TARGET_DIR}/$appname" 2 0
                ln -svfT ${TARGET_DIR}/$APP_DIR ${TARGET_DIR}/$appname
        fi
else
        echof "解压的目录的release格式不对, 不能链接" 1 0
fi

# 判断给定的应用名是否存在
# 加入PATH目录
if [ $BIN -eq 1 ]; then
        find_bin_count=$(find ${TARGET_DIR}/$appname/ -maxdepth 1 -type d -name bin | wc -l)
        if [ $find_bin_count -ge 1 ]; then
                echof "将${TARGET_DIR}/$appname/bin:${TARGET_DIR}/$appname/sbin 加入PATH目录, 需要重新登入shell" 1 0
                echo -n "export PATH=${TARGET_DIR}/$appname/bin:${TARGET_DIR}/$appname/sbin" > /etc/profile.d/$appname.sh
                echo ':$PATH' >> /etc/profile.d/$appname.sh
        else
                echo -n "export PATH=${TARGET_DIR}/$appname" > /etc/profile.d/$appname.sh
                echo ':$PATH' >> /etc/profile.d/$appname.sh
                echof "${TARGET_DIR}/$appname 目录中没有bin, sbin目录，导出默认目录" 2 0
        fi
fi

# 链接include
if [ $INCLUDE -eq 1 ]; then
        find_inc_count=$(find ${TARGET_DIR}/$appname/ -maxdepth 1 -type d -name include | wc -l)
        if [ $find_bin_count -ge 1 ]; then
                echof "将${TARGET_DIR}/$appname/include, 导出" 1 0
                ln -svfT ${TARGET_DIR}/$appname/include /usr/include/$appname
        else
                echof "${TARGET_DIR}/$appname 中不存在include文件" 1 1
        fi
fi

# 导出库文件
if [ $LIB -eq 1 ]; then
        find_lib_count=$(find ${TARGET_DIR}/$appname/ -maxdepth 1 -type d -name lib | wc -l)
        if [ $find_lib_count -ge 1 ]; then
                echof "将${TARGET_DIR}/$appname/lib, 导出" 1 0
                ln -svfT ${TARGET_DIR}/$appname/include /usr/include/$appname
                echo -e "${TARGET_DIR}/$appname/lib\n${TARGET_DIR}/$appname/lib64" > /etc/ld.so.conf.d/$appname.conf
                ldconfig -v | grep $appname -C 10
        else
                echof "${TARGET_DIR}/$appname 中不存在lib文件" 1 1
        fi
fi



# 生成systemd脚本
if [ $SYSTEMD -eq 1 ]; then
        echof "添加支持systemd 脚本 /etc/systemd/system/$appname.service" 1 0
        _PROG=$(echo "$PROG" | tr -s ' ' , | cut -d, -f1)
        PROG_=$(basename ${_PROG})
        PROG_PATH=$(find ${TARGET_DIR}/$appname/  -name $PROG_ -type f -perm 755)
        PROG=$(echo "$PROG" | sed -r "s@${_PROG}(.*)@${PROG_PATH}\1@")
        if [ -z "$PROG_PATH" ]; then
                echof "检查依赖, 提供的服务的二进制程序名不对, 不能安装"
        fi
cat <<EOF > /etc/systemd/system/$appname.service
[Unit]
Description=$appname Service By $(basename $0). 2192383945@qq.com

[Service]
Type=simple
WorkingDirectory=${TARGET_DIR}/$appname/
EnvironmentFile=-/etc/sysconfig/$appname
ExecStart=$PROG
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
#Restart=on-failure
#RestartSec=42s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl cat $appname.service
systemctl status $appname.service
systemctl start $appname.service
systemctl enable $appname.service
" 2 0
fi
