#!/usr/bin/env bash

# Program: MySQL 全量增量恢复脚本，基于对应的备份脚本使用 使用 percona xtrabackup
# Author : Menglc
# Date   : 2020-08-28


# 读取配置文件中的所有变量值, 设置为全局变量
# 配置文件
conf_file="../conf/mysql_recovery_backup.conf"
# mysql 用户
#user=`sed '/^user=/!d;s/.*=//' $conf_file`
# mysql 密码
#password=`sed '/^password=/!d;s/.*=//' $conf_file`
# mysql 要恢复的备份目录
backup_dir=`sed '/^backup_dir=/!d;s/.*=//' $conf_file`
# percona-xtrabackup要链接的mysql_socket路径
mysql_socket=`sed '/^mysql_socket=/!d;s/.*=//' $conf_file`
# mysql 全备恢复前缀标识
full_recovery_prefix=`sed '/^full_recovery_prefix=/!d;s/.*=//' $conf_file`
# mysql 增量备份恢复前缀标识
increment_recovery_prefix=`sed '/^increment_recovery_prefix=/!d;s/.*=//' $conf_file`
# mysql 配置文件
mysql_conf_file=`sed '/^mysql_conf_file=/!d;s/.*=//' $conf_file`
# 备份错误日志文件
error_log=`sed '/^error_log=/!d;s/.*=//' $conf_file`
# 备份索引文件
index_file=`sed '/^index_file=/!d;s/.*=//' $conf_file`
# 恢复索引文件
recovery_tmp_index_file=`sed '/^recovery_tmp_index_file=/!d;s/.*=//' $conf_file`

# 恢复索引文件
recovery_index_file=`sed '/^recovery_index_file=/!d;s/.*=//' $conf_file`

log_dir=../log
var_dir=../var
mkdir -p $log_dir
mkdir -p $var_dir

# 恢复日期
backup_date=`date +%F`
# 恢复日期
backup_time=`date +%H-%M-%S`
# 恢复日期
backup_week_day=`date +%u`

#查询出全备的目录
recovery_full_folder=`grep "full_" $index_file | \
                   awk -F '[, {}]*' '{print $3}' | \
                   awk -F ':' '{print $2}'`


# 全量备份恢复
function full_recovery_backup() {
  $xtrabackup_dir/bin/innobackupex \
    --defaults-file=$mysql_conf_file \
	--apply-log \
	--redo-only \
	$backup_dir/$recovery_full_folder  > $log_dir/recovery_${recovery_full_folder}.log 2>&1
  return $?
}

# 增量备份恢复
function increment_recovery_backup() {
	cp $index_file $recovery_tmp_index_file
	while grep "incr_" $recovery_tmp_index_file &> /dev/null;do
	incr_base_folder=`grep incr_ $recovery_tmp_index_file | \
                   head -n 1 | \
                   awk -F '[, {}]*' '{print $3}' | \
                   awk -F ':' '{print $2}'`
		$xtrabackup_dir/bin/innobackupex \
		--defaults-file=$mysql_conf_file \
		--apply-log \
		--redo-only \
		$backup_dir/$recovery_full_folder \
		--incremental-dir=$backup_dir/$incr_base_folder > $log_dir/recovery_${incr_base_folder}.log 2>&1
	recovery_ok=$?
	if [ 0 -eq "$recovery_ok" ]; then
	append_index_to_file ${increment_recovery_prefix}
	else
	# 全备失败
	logging_backup_err ${increment_recovery_prefix}
	return 1
	fi
	sed -i "/$incr_base_folder/d" $recovery_tmp_index_file
	done
  return $?
}

# 判断是应该单次全量恢复还是增量全量恢复
# 0:full, 1:incr
function get_backup_type() {
  
  backup_type=0
  grep -v "full_" $index_file &> /dev/null
  if [ $? -eq 1 ]; then
    backup_type=0
  else
    backup_type=1
  fi
  if [ ! -n "`cat $index_file`" ]; then
	backup_type=2
  fi
  return $backup_type
}

# 记录 错误消息到文件
function logging_backup_err() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >> $error_log
}

# 备份索引文件
function backup_index_file() {
  cp $recovery_index_file ${recovery_index_file}_$(date -d "1 day ago" +%F)
}

# 备份索引文件
function send_index_file_to_remote() {
  echo 'send index file ok'
}

# 添加索引, 索引记录了当前最新的备份
function append_index_to_file() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >> $recovery_index_file
}

# 记录 错误消息到文件
function logging_backup_err() {
  echo "{week_day:$backup_week_day, \
         dir:${1}_${backup_date}_${backup_time}_${backup_week_day}, \
         type:${1}, \
         date:${backup_date}}" >> $error_log
}

# 清空索引
function purge_index_from_file() {
  > $recovery_index_file
}

# 清空错误日志信息
function purge_err_log() {
  > $error_log
}

# 测试配置文件正确性
function test_conf_file() {
  # 判断每个变量是否在配置文件中有配置，没有则退出程序
#  if [ ! -n "$user" ]; then echo 'fail: configure file user not set'; exit 2; fi
#  if [ ! -n "$password" ]; then echo 'fail: configure file password not set'; exit 2; fi
  if [ ! -n "$backup_dir" ]; then echo 'fail: configure file backup_dir not set'; exit 2; fi
  if [ ! -n "$full_recovery_prefix" ]; then echo 'fail: configure file full_recovery_prefix not set'; exit 2; fi
  if [ ! -n "$increment_recovery_prefix" ]; then echo 'fail: configure file increment_recovery_prefix not set'; exit 2; fi
  if [ ! -n "$mysql_conf_file" ]; then echo 'fail: configure file mysql_conf_file not set'; exit 2; fi
  if [ ! -n "$error_log" ]; then echo 'fail: configure file error_log not set'; exit 2; fi
  if [ ! -n "$index_file" ]; then echo 'fail: configure file index_file not set'; exit 2; fi
  if [ ! -n "$recovery_tmp_index_file" ]; then echo 'fail: configure file recovery_tmp_index_file not set'; exit 2; fi
  if [ ! -n "$recovery_index_file" ]; then echo 'fail: configure file recovery_index_file not set'; exit 2; fi
 
}
# 执行
function run() {
  # 检测配置文件值
  test_conf_file

  # 判断是执行全备还是增量备份
  get_backup_type
  backup_type=$?
case $backup_type in
    0 )
      # 全量备份
      full_recovery_backup 
      backup_ok=$?
      if [ 0 -eq "$backup_ok" ]; then
      # 全备成功
        # # 打包最新备份
        # tar_backup_file $full_backup_prefix
        # # 将tar备份发送到远程
        # send_backup_to_remote $full_backup_prefix
        # 备份索引文件
        backup_index_file
        # 清除索引文件
        purge_index_from_file
        # 添加索引, 索引记录了当前最新的备份
        append_index_to_file ${full_recovery_prefix}
		echo "全量恢复完成"
		cat $backup_dir/$recovery_full_folder/xtrabackup_checkpoints
      else
      # 全备失败
		echo "全量恢复失败，请查看对应的日志"
        logging_backup_err ${full_recovery_prefix}
      fi
      ;;
    1 )
		# 增量备份
		full_recovery_backup
		backup_ok=$?
		if [ 0 -eq "$backup_ok" ]; then
			append_index_to_file ${full_recovery_prefix}
		else
			# 全备失败
			logging_backup_err ${full_recovery_prefix}
		fi
		increment_recovery_backup 
		backup_ok=$?
		if [ 0 -eq "$backup_ok" ]; then
		# 备份索引文件
        backup_index_file
        # 清除索引文件
        purge_index_from_file
			echo "增量全量恢复完成"
			cat $backup_dir/$recovery_full_folder/xtrabackup_checkpoints
			cat $backup_dir/$incr_base_folder/xtrabackup_checkpoints
		else
		# 记录错误日志
			echo "增量全量恢复失败，请查看对应的日志"
			logging_backup_err $increment_prefix
		fi
		  ;;
	2)
		echo "请先备份mysql数据库在进行恢复数据操作"
	;;
  esac
}

run
