#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用sudo运行此脚本"
        exit 1
    fi
}

show_banner() {
    echo "=========================================="
    echo "          noVNC 一键卸载脚本"
    echo "          (全自动模式)"
    echo "=========================================="
    echo ""
}

stop_services() {
    log_info "停止noVNC服务..."
    
    # 停止并禁用服务
    if systemctl is-active --quiet novnc 2>/dev/null; then
        systemctl stop novnc
        log_info "已停止novnc服务"
    fi
    
    if systemctl is-enabled --quiet novnc 2>/dev/null; then
        systemctl disable novnc
        log_info "已禁用novnc服务"
    fi
    
    # 停止其他可能的noVNC服务
    for service in novnc@* novnc-* websockify; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            systemctl stop "$service"
            log_info "已停止服务: $service"
        fi
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            systemctl disable "$service"
            log_info "已禁用服务: $service"
        fi
    done
    
    # 终止相关进程
    log_info "终止noVNC相关进程..."
    pkill -f "websockify.*6080" || true
    pkill -f "novnc_proxy" || true
    pkill -f "python.*no[vV]NC" || true
    pkill -f ".*6080.*" || true
    
    sleep 2
    
    # 强制终止残留进程
    for proc in websockify novnc_proxy; do
        if pgrep -f "$proc" >/dev/null; then
            pkill -9 -f "$proc"
            log_info "已强制终止 $proc 进程"
        fi
    done
}

remove_systemd_services() {
    log_info "删除systemd服务..."
    
    # 查找所有可能的noVNC服务文件
    local service_files=(
        "/etc/systemd/system/novnc.service"
        "/etc/systemd/system/novnc@.service"
        "/etc/systemd/system/novnc-*.service"
        "/lib/systemd/system/novnc.service"
        "/lib/systemd/system/novnc@.service"
        "/lib/systemd/system/novnc-*.service"
        "/usr/lib/systemd/system/novnc.service"
        "/usr/lib/systemd/system/novnc@.service"
        "/usr/lib/systemd/system/novnc-*.service"
    )
    
    for pattern in "${service_files[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_info "已删除服务文件: $file"
            fi
        done
    done
    
    # 删除服务配置目录
    if [[ -d "/etc/systemd/system/novnc.service.d" ]]; then
        rm -rf "/etc/systemd/system/novnc.service.d"
        log_info "已删除服务配置目录"
    fi
    
    # 删除可能的其他配置目录
    find /etc/systemd/system -name "*novnc*" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # 重新加载systemd
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
}

remove_packages() {
    log_info "卸载noVNC相关软件包..."
    
    # 查找并卸载所有相关包
    local packages_to_remove=()
    
    # 使用dpkg查找相关包
    for pkg in $(dpkg -l | grep -E "(novnc|websockify|no-vnc)" | awk '{print $2}'); do
        packages_to_remove+=("$pkg")
    done
    
    # 添加常见包名
    local common_packages=(
        "novnc"
        "novnc-lite"
        "python3-novnc"
        "websockify"
        "python3-websockify"
        "no-vnc"
    )
    
    for pkg in "${common_packages[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            packages_to_remove+=("$pkg")
        fi
    done
    
    # 去重并卸载
    if [ ${#packages_to_remove[@]} -gt 0 ]; then
        unique_packages=($(printf "%s\n" "${packages_to_remove[@]}" | sort -u))
        log_info "发现以下软件包将被卸载: ${unique_packages[*]}"
        apt-get remove --purge -y "${unique_packages[@]}"
    else
        log_info "未发现需要卸载的软件包"
    fi
    
    # 清理
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean -y 2>/dev/null || true
}

remove_files() {
    log_info "删除noVNC相关文件和目录..."
    
    # 要删除的目录
    local dirs=(
        "/usr/share/novnc"
        "/usr/share/noVNC"
        "/var/lib/novnc"
        "/var/log/novnc"
        "/etc/novnc"
        "/opt/novnc"
        "/opt/noVNC"
        "/usr/local/share/novnc"
        "/usr/local/share/noVNC"
        "/usr/local/novnc"
        "/usr/local/noVNC"
    )
    
    # 要删除的文件
    local files=(
        "/usr/local/bin/start_novnc.sh"
        "/usr/local/bin/novnc_proxy"
        "/usr/local/bin/websockify"
        "/usr/bin/novnc_proxy"
        "/usr/bin/websockify"
        "/usr/sbin/novnc"
        "/etc/init.d/novnc"
        "/etc/default/novnc"
        "/tmp/websockify"
        "/tmp/novnc"
        "/tmp/noVNC"
    )
    
    # 删除目录
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "已删除目录: $dir"
        fi
    done
    
    # 删除文件
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "已删除文件: $file"
        fi
    done
    
    # 删除用户目录中的noVNC
    for home_dir in /home/* /root; do
        if [[ -d "$home_dir/noVNC" ]]; then
            rm -rf "$home_dir/noVNC"
            log_info "已删除 $home_dir/noVNC"
        fi
        if [[ -d "$home_dir/novnc" ]]; then
            rm -rf "$home_dir/novnc"
            log_info "已删除 $home_dir/novnc"
        fi
    done
    
    # 查找并删除其他可能的文件
    find /usr/local/bin /usr/bin /usr/sbin -name "*novnc*" -exec rm -f {} + 2>/dev/null || true
    find /usr/local/bin /usr/bin /usr/sbin -name "*websockify*" -exec rm -f {} + 2>/dev/null || true
}

remove_certificates() {
    log_info "清理证书文件..."
    
    local cert_files=(
        "self.pem"
        "novnc.pem"
        "/etc/ssl/novnc/cert.pem"
        "/etc/ssl/novnc/key.pem"
        "/etc/ssl/certs/novnc*"
        "/etc/ssl/private/novnc*"
        "/etc/novnc/ssl/cert.pem"
        "/etc/novnc/ssl/key.pem"
    )
    
    for cert in "${cert_files[@]}"; do
        for file in $cert; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_info "已删除证书: $file"
            fi
        done
    done
    
    # 删除空目录
    for dir in "/etc/ssl/novnc" "/etc/novnc/ssl"; do
        if [[ -d "$dir" ]]; then
            rmdir --ignore-fail-on-non-empty "$dir" 2>/dev/null || true
        fi
    done
}

verify_uninstall() {
    log_info "验证卸载结果..."
    echo "------------------------------------------"
    
    local errors_found=0
    
    # 检查进程
    if pgrep -f "websockify\|novnc_proxy\|no[vV]NC" >/dev/null; then
        log_error "发现残留的noVNC进程:"
        pgrep -fa "websockify\|novnc_proxy\|no[vV]NC" || true
        errors_found=1
    else
        log_info "✓ 无noVNC相关进程运行"
    fi
    
    # 检查端口
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp | grep -q ":6080"; then
            log_error "端口6080仍在监听:"
            ss -tlnp | grep ":6080" || true
            errors_found=1
        else
            log_info "✓ 端口6080未监听"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":6080"; then
            log_error "端口6080仍在监听:"
            netstat -tlnp 2>/dev/null | grep ":6080" || true
            errors_found=1
        else
            log_info "✓ 端口6080未监听"
        fi
    fi
    
    # 检查systemd服务
    if systemctl list-unit-files | grep -i novnc >/dev/null 2>&1; then
        log_error "发现systemd服务残留:"
        systemctl list-unit-files | grep -i novnc || true
        errors_found=1
    else
        log_info "✓ 无systemd服务残留"
    fi
    
    # 检查软件包
    if dpkg -l | grep -i -E "novnc|websockify" >/dev/null 2>&1; then
        log_error "发现软件包残留:"
        dpkg -l | grep -i -E "novnc|websockify" || true
        errors_found=1
    else
        log_info "✓ 无软件包残留"
    fi
    
    # 检查文件残留
    local found_dirs=0
    for path in /usr/share/novnc /usr/share/noVNC /etc/novnc /opt/novnc /opt/noVNC; do
        if [[ -d "$path" ]]; then
            log_error "发现目录残留: $path"
            found_dirs=1
            errors_found=1
        fi
    done
    
    if [[ $found_dirs -eq 0 ]]; then
        log_info "✓ 无重要目录残留"
    fi
    
    echo "------------------------------------------"
    
    if [[ $errors_found -eq 0 ]]; then
        log_info "✓ 卸载验证通过"
    else
        log_warn "⚠ 发现一些残留项目，建议手动清理"
    fi
}

cleanup_logs() {
    log_info "清理日志文件..."
    
    # 清理系统日志中的noVNC相关条目
    for log_file in /var/log/syslog /var/log/messages /var/log/daemon.log; do
        if [[ -f "$log_file" ]]; then
            sed -i '/novnc\|noVNC\|websockify/d' "$log_file" 2>/dev/null || true
        fi
    done
    
    # 删除日志目录
    rm -rf /var/log/novnc* 2>/dev/null || true
    
    log_info "日志清理完成"
}

main() {
    show_banner
    check_root
    
    log_warn "开始自动卸载noVNC..."
    log_warn "此操作将完全卸载noVNC，无需确认"
    echo ""
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行卸载步骤
    stop_services
    remove_systemd_services
    remove_packages
    remove_files
    remove_certificates
    cleanup_logs
    
    # 短暂等待确保清理完成
    sleep 1
    
    # 验证结果
    verify_uninstall
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_info "noVNC 卸载完成!"
    log_info "耗时: ${duration}秒"
    log_info "注意: VNC服务(5901端口)仍然保持运行状态"
    echo ""
    log_info "脚本执行完毕，退出"
}

# 自动执行主函数
main "$@"