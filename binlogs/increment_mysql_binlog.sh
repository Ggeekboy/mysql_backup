#!/bin/bash
#
# Function：实现mysql二进制文件备份，基于mysqldump备份出来的备份文件
# Author : menglc
# Notes：
# Date   : 2020-08-27

# 定义备份使用到的相关变量（需要根据用户实际环境做相应的修改）
#mysqldump备份的备份文件所在的目录
backup_data=/backup/mysql/full
backup_binlog=/backup/mysql/logbin/$(date +"%F")
mysql_binlog=/mysql/binlogs
logfile=/var/log/mysqldump.log
mysqldump_conf=/etc/mysqldump.conf
# 函数定义

########################[Mysql 二进制日志备份]#####################
bin_backup(){
! [ -d $backup_binlog ] && mkdir -p $backup_binlog
#备份文件当前的bin_log文件是那一个，在打包的时候就打包这个及之后文件
#bin_log=$(grep '\-\- CHANGE MASTER TO MASTER_LOG_FILE=' /backup/mysql/full/full-2020-08-24-18-11-06.sql | cut -d \' -f 2)
#bin_log=$(grep '\-\- CHANGE MASTER TO MASTER_LOG_FILE=' /backup/mysql/full/full-2020-08-24-18-11-06.sql| awk -F \' '{print$2}')
backup_name=$(grep "backup=" $mysqldump_conf | awk -F = '{print$2}')
index=$(grep '\-\- CHANGE MASTER TO MASTER_LOG_FILE=' $backup_data/$backup_name| awk -F \' '{print$2}' | awk -F . '{print$2}')
for file in /mysql/binlogs/*.0*
do
	num1=$(echo $file | awk -F . '{print$2}')
	if [ $index -le $num1 ];then
		cp -a $file $backup_binlog
		#echo "$index>$num1"	
	fi	
done
if grep "binlog" $mysqldump_conf;then
sed -i "s|bin_log_pos=.*|bin_log_pos=$file|" $mysqldump_conf
else
sed -i  "2a[binlog]\nbin_log_pos=$file" $mysqldump_conf
fi

if [ -e /usr/bin/bunzip2 ];then
echo "bzip2已经安装"
else
yum install -y bzip2
fi

cd $backup_binlog
tar -jcf bin-`date +"%F-%H-%M-%S"`.tar.bz2 * &> /dev/null
[ -n $backup_binlog] && \rm -rf $backup_binlog/*.0*
#\mv -f bin*.tar.bz2 $backup_binlog
}

########################[Mysql 二进制日志备份]#####################

# 主函数main

bin_backup
if [ $? -eq 0 ];then
    echo "$(date +"%F %H:%M:%S") [Note] MySQL binary log file backup is finished " >> $logfile
    chmod -R 600 $backup_binlog
else
    echo "$(date +"%F %H:%M:%S") [Warning] Mysql binary log file backup is not completed" | tee -a $logfile | mail -s "mysql binary log backup failed" root@`hostname`
fi

