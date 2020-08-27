#!/bin/bash
#
# Function：实现mysql完全备份
# Notes：

# 定义备份使用到的相关变量（需要根据用户实际环境做相应的修改）
backup_data=/backup/mysql/full
backup_binlog=/backup/mysql/logbin
mysql_binlog=/mysql/binlogs/
mysql_bin_path=`ps -ef | grep -E "mysqld[[:space:]]+" | awk -F ' ' '{ print $8 }' | sed -r 's@[^/]+/?$@@'`
mysql_user=root
mysql_password=123456
logfile=/var/log/mysqldump.log
mysqldump_conf=/etc/mysqldump.conf
# 函数定义

########################[本地MySQL健康检测]######################
function health_check() {
if pgrep mysqld &> /dev/null;then
#   mysqld_pid=`pgrep -l mysqld | grep -E "mysqld\>" | awk '{ print $1 }'`
	mysqld_pid=`pgrep mysqld`
    echo "$(date +"%F %H:%M:%S") $mysqld_pid [Note] Server Mysql is Running ..." >> $logfile
else
    service mysqld start &> /dev/null || echo "$(date +"%F %H:%M:%S") [Warning] Server MySQL is not running, backup failed" >> $logfile && return 5
fi
}
backup_name=full-`date +"%F-%H-%M-%S"`.sql
#######################[mysqldump完全备份]###################
function full_backup(){
[ ! -d $backup_data ] && mkdir -p $backup_data
${mysql_bin_path}mysqldump -u$mysql_user -p$mysql_password --all-databases --lock-all-tables  --flush-logs --master-data=2 \
--triggers --routines --events --set-gtid-purged=off -r ${backup_data}/$backup_name &> /dev/null
##写入配置文件用于增量更新读取
if ! [ -e $mysqldump_conf ];then
cat > $mysqldump_conf << EOF
[full]
backup=${backup_name}
EOF
else
sed -i "s|backup=.*|backup=${backup_name}|" $mysqldump_conf
fi
if grep -q "CHANGE MASTER TO" ${backup_data}/$backup_name ;then
    return 0
else
    return 5
fi
}

########################[Mysql 二进制日志备份]#####################
function bin_backup(){
[ ! -d $backup_binlog ] && mkdir -p $backup_binlog
cd $mysql_binlog
if  [ ! -e /usr/bin/bunzip2 ];then
yum install -y bzip2
else
echo "bzip2已经安装"
fi
#yum install -y bzip2
tar -jcf bin-`date +"%F-%H-%M-%S"`.tar.bz2 * &> /dev/null
\mv -f bin*.tar.bz2 $backup_binlog
}


########################[Mysql 二进制日志备份]#####################

# 主函数main
function run (){
health_check
if [ $? -eq 0 ];then
    echo "$(date +"%F %H:%M:%S") [Note] MySQL full backup start ..." >> $logfile
else
    echo "$(date +"%F %H:%M:%S") [Warning] Server MySQL is not running, backup failed" | mail -s "mysql backup is failed" root@`hostname`
fi
full_backup
if [ $? -eq 0 ];then
    echo "$(date +"%F %H:%M:%S") [Note] MySQL full backup is finished" >> $logfile
    chmod -R 600 $backup_data
else
    echo "$(date +"%F %H:%M:%S") [Warning] Function full_backup() execution failed, backup was interrupted"  | tee -a $logfile | mail -s "mysql backup is failed" root@`hostname`
fi
echo "$(date +"%F %H:%M:%S") [Note] MySQL binary log file backup is started ..." >> $logfile
bin_backup
if [ $? -eq 0 ];then
    echo "$(date +"%F %H:%M:%S") [Note] MySQL binary log file backup is finished " >> $logfile
    chmod -R 600 $backup_binlog
else
    echo "$(date +"%F %H:%M:%S") [Warning] Mysql binary log file backup is not completed" | tee -a $logfile | mail -s "mysql binary log backup failed" root@`hostname`
fi
}
run
