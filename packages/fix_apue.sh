#!/bin/bash
# fix_apue.sh - 一键修复 APUE 3e 在 Ubuntu 24.04 上的所有编译问题
# 用法：可以放在任意位置，自动查找 apue.3e 目录

set -e  # 遇到错误立即退出

# 颜色输出（如果支持）
if [ -t 1 ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	NC=''
fi

print_info() {
	echo "${GREEN}[INFO]${NC} $1"
}

print_warn() {
	echo "${YELLOW}[WARN]${NC} $1"
}

print_error() {
	echo "${RED}[ERROR]${NC} $1"
}

# 查找 apue.3e 目录
find_apue_dir() {
	# 1. 检查当前目录
	if [ -f "apue.3e/Makefile" ] && [ -d "apue.3e/include" ]; then
		echo "apue.3e"
		return 0
	fi

	# 2. 检查当前目录是否就是 apue.3e
	if [ -f "Makefile" ] && [ -d "include" ] && grep -q "apue" Makefile 2>/dev/null; then
		echo "."
		return 0
	fi

	# 3. 检查父目录
	if [ -f "../apue.3e/Makefile" ] && [ -d "../apue.3e/include" ]; then
		echo "../apue.3e"
		return 0
	fi

	# 4. 在当前目录及父目录中搜索
	local found=$(find . -maxdepth 2 -type d -name "apue.3e" -exec test -f {}/Makefile \; -print -quit 2>/dev/null)
	if [ -n "$found" ]; then
		echo "$found"
		return 0
	fi

	# 5. 在常见位置搜索
	local common_paths="/usr/local/src/apue.3e /opt/apue.3e $HOME/apue.3e $HOME/src/apue.3e"
	for path in $common_paths; do
		if [ -f "$path/Makefile" ] && [ -d "$path/include" ]; then
			echo "$path"
			return 0
		fi
	done

	return 1
}

# 获取 apue 源码目录
print_info "正在查找 apue.3e 源码目录..."
APUE_DIR=$(find_apue_dir)

if [ -z "$APUE_DIR" ]; then
	print_error "未找到 apue.3e 源码目录！"
	echo ""
	echo "请确保："
	echo "  1. 源码目录名为 'apue.3e'"
	echo "  2. 目录中包含 Makefile 和 include/apue.h"
	echo ""
	echo "您可以手动指定目录："
	echo "  export APUE_DIR=/path/to/apue.3e"
	echo "  $0"
	exit 1
fi

# 转换为绝对路径
APUE_DIR=$(cd "$APUE_DIR" && pwd)
print_info "找到源码目录: $APUE_DIR"

# 进入源码目录
cd "$APUE_DIR"

# 检查必要文件
if [ ! -f "Makefile" ] || [ ! -d "include" ]; then
	print_error "$APUE_DIR 不是有效的 apue.3e 源码目录"
	exit 1
fi

print_info "开始修复 APUE 3e 源码..."

# 1. 移除所有 Makefile 中的 -Werror（将警告当作错误）
print_info "移除 Makefile 中的 -Werror 标志..."
find . -name "Makefile" -exec sed -i 's/-Werror//g' {} \;

# 2. 移除 -ansi 标志（避免 ANSI C 标准导致的兼容性问题）
print_info "移除 -ansi 标志..."
find . -name "Makefile" -exec sed -i 's/-ansi//g' {} \;

# 3. 修复 threads/badexit2.c
if [ -f "threads/badexit2.c" ]; then
	print_info "修复 threads/badexit2.c..."
	sed -i 's/pthread_exit((void \*)1);/pthread_exit((void *)(intptr_t)1);/' threads/badexit2.c
fi

# 4. 修复 stdio/buf.c
if [ -f "stdio/buf.c" ]; then
	print_info "修复 stdio/buf.c..."
	sed -i '/#include "apue.h"/a #undef _IOFBF\n#undef _IOLBF\n#undef _IONBF' stdio/buf.c
fi

# 5. 修复 threads/exitstatus.c
if [ -f "threads/exitstatus.c" ]; then
	print_info "修复 threads/exitstatus.c..."
	sed -i 's/return((void \*)0);/return((void *)(intptr_t)0);/' threads/exitstatus.c
	sed -i 's/return((void \*)1);/return((void *)(intptr_t)1);/' threads/exitstatus.c
fi

# 6. 修复 major/minor 宏问题（新版 glibc 需要 sys/sysmacros.h）
print_info "添加 sys/sysmacros.h 头文件..."
find . -name "*.c" -exec sed -i '/#include <sys\/types.h>/a #include <sys\/sysmacros.h>' {} \;

# 7. 修复 db 目录的 macOS 特有编译选项
if [ -f "db/Makefile" ]; then
	print_info "修复 db/Makefile (Linux 共享库兼容)..."
	# 备份原文件
	cp db/Makefile db/Makefile.bak 2>/dev/null || true

	# 修改共享库编译选项
	sed -i 's/-Wl,-dylib/-shared/g' db/Makefile

	# 修改库文件名格式
	sed -i 's/\.so\.1/\.so\.1.0/g' db/Makefile

	# 添加符号链接创建
	if ! grep -q "ln -sf" db/Makefile; then
		sed -i '/libapue_db.so.1.0:/a \\tln -sf libapue_db.so.1.0 libapue_db.so' db/Makefile
	fi
fi

# 8. 修复其他可能的问题：添加缺失的函数声明
if [ -f "include/apue.h" ]; then
	print_info "修复 apue.h 头文件..."
	# 检查是否已有 pr_mask 声明
	if ! grep -q "void pr_mask" include/apue.h; then
		sed -i '/#endif/i void pr_mask(const char *);' include/apue.h
	fi
fi

# 9. 修复调用者ID程序的头文件问题
if [ -f "termios/callerid.c" ]; then
	print_info "修复 termios/callerid.c..."
	sed -i '/#include <termios.h>/a #include <sys/ioctl.h>' termios/callerid.c
fi

# 10. 处理 sock 目录可能的问题
if [ -f "sock/Makefile" ]; then
	print_info "修复 sock/Makefile..."
	sed -i 's/-lresolv//g' sock/Makefile
fi

print_info "所有修复完成！"
echo ""
print_info "开始编译 APUE 源码..."
echo ""

# 清理之前的编译产物
make clean 2>/dev/null || true

# 执行编译
if make 2>&1 | tee build.log; then
	echo ""
	print_info "✓ 编译成功！"
	echo ""

	# 检查是否生成了 libapue.a
	if [ -f "lib/libapue.a" ]; then
		print_info "静态库已生成: $APUE_DIR/lib/libapue.a"

		# 询问是否安装到系统目录（使用兼容方式）
		echo ""
		printf "%s" "是否将头文件和库安装到 /usr/local ? (y/N): "
		read answer
		echo ""
		if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
			print_info "安装头文件到 /usr/local/include ..."
			cp include/apue.h /usr/local/include/

			print_info "安装静态库到 /usr/local/lib ..."
			cp lib/libapue.a /usr/local/lib/

			# 如果生成了 db 库，也一并安装
			if [ -f "db/libapue_db.so.1.0" ]; then
				cp db/libapue_db.so.1.0 /usr/local/lib/
				ln -sf /usr/local/lib/libapue_db.so.1.0 /usr/local/lib/libapue_db.so
			fi

			print_info "安装完成！现在可以在任何地方使用 -lapue 编译程序了"
			echo ""
			print_info "测试编译："
			echo "  gcc your_program.c -o your_program -lapue"
		else
			print_info "跳过安装。您可以稍后手动安装："
			echo "  sudo cp $APUE_DIR/include/apue.h /usr/local/include/"
			echo "  sudo cp $APUE_DIR/lib/libapue.a /usr/local/lib/"
		fi
	else
		print_warn "libapue.a 未生成，请检查编译日志"
	fi
else
	print_error "编译失败！"
	echo ""
	print_info "请查看 $APUE_DIR/build.log 文件获取详细错误信息"
	echo "前20行错误信息："
	head -20 build.log
	exit 1
fi
