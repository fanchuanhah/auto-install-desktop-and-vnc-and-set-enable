#!/bin/bash
# ==================================================
# Ubuntu 桌面环境一键安装脚本（多桌面 + VNC + noVNC + 应用安装）
# 版本: 0.1-bete
# ==================================================

AUTO_DESKTOP_TYPE="xfce4"
AUTO_BROWSER_CHOICE="firefox"
AUTO_INSTALL_COMMON_SOFT="n"
AUTO_INSTALL_VNC="y"
AUTO_VNC_PORT="5901"
AUTO_VNC_GEOMETRY="1280x800"
AUTO_VNC_DEPTH="16"
AUTO_VNC_ZLIB="9"
AUTO_VNC_LOCALHOST="no"
AUTO_VNC_PASSWORD="123456"
AUTO_VNC_START_NOW="y"
AUTO_INSTALL_LANG="y"
AUTO_INSTALL_NOVNC="y"
AUTO_NOVNC_PORT="6080"                     # 新增：noVNC 默认端口

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

declare -a QUESTION_STACK
declare -g CURRENT_STEP=""
declare -g BACK_TO_PREV=0
declare -g CURRENT_USER=$(whoami)
declare -g CURRENT_HOME=$HOME
declare -g TARGET_USER=""
declare -g TARGET_HOME=""
declare -g LOCKFILE=""
declare -g DESKTOP_TYPE=""
declare -g DESKTOP_CMD=""
declare -g BROWSER_CHOICE=""
declare -g INSTALL_COMMON_SOFT=""
declare -g INSTALL_VNC=""
declare -g VNC_PORT=""
declare -g VNC_DISPLAY=""
declare -g VNC_GEOMETRY=""
declare -g VNC_DEPTH=""
declare -g VNC_ZLIB=""
declare -g VNC_LOCALHOST=""
declare -g VNC_PASSWORD=""
declare -g VNC_START_NOW=""
declare -g INSTALL_LANG=""
declare -g INSTALL_NOVNC=""
declare -g INSTALL_INPUT_METHOD=""
declare -g NOVNC_PORT=""

print_info() { echo -e "${GREEN}[信息]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_title() { echo -e "\n${CYAN}========== $1 ==========${NC}\n"; }

reset_question_stack() {
    QUESTION_STACK=()
    CURRENT_STEP=""
    BACK_TO_PREV=0
}

push_question() {
    local qid="$1"
    if [[ "$CURRENT_STEP" != "" ]]; then
        QUESTION_STACK+=("$CURRENT_STEP")
    fi
    CURRENT_STEP="$qid"
}

pop_question() {
    if [[ ${#QUESTION_STACK[@]} -gt 0 ]]; then
        CURRENT_STEP="${QUESTION_STACK[-1]}"
        unset 'QUESTION_STACK[-1]'
    else
        CURRENT_STEP=""
    fi
}

clear_screen() {
    clear
    echo -e "${PURPLE}Ubuntu 桌面环境安装工具 (多桌面+VNC+应用)${NC}\n"
}

ask_yes_no() {
    local prompt="$1 (y/n/r) [默认: y]: "
    local qid="$2"
    local default="y"
    local answer
    
    push_question "$qid"
    while true; do
        read -p "$prompt" -r answer
        answer=${answer:-$default}
        
        if [[ "$answer" =~ ^[Rr]$ ]]; then
            pop_question
            echo "返回上一个问题..."
            BACK_TO_PREV=1
            return 1
        fi
        
        if [[ "$answer" =~ ^[YyNn]$ ]]; then
            break
        else
            print_error "无效输入！请输入 y/n/r"
        fi
    done
    
    [[ "$answer" =~ ^[Yy]$ ]] && return 0 || return 2
}

ask_input() {
    local prompt="$1"
    local qid="$2"
    local default="$3"
    local answer
    
    push_question "$qid"
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [默认: $default]: " -r answer
        else
            read -p "$prompt: " -r answer
        fi
        answer=${answer:-$default}
        
        if [[ "$answer" =~ ^[Rr]$ ]]; then
            pop_question
            echo "返回上一个问题..."
            BACK_TO_PREV=1
            return 1
        fi
        
        if [[ -z "$answer" && "$qid" =~ "username" ]]; then
            print_error "该选项不能为空，请重新输入！"
        else
            break
        fi
    done
    
    echo "$answer"
    return 0
}

confirm_action() {
    local prompt="$1 [y/n/r]: "
    local qid="$2"
    local answer
    
    push_question "$qid"
    while true; do
        read -p "$prompt" -r answer
        answer=${answer:-n}
        
        if [[ "$answer" =~ ^[Rr]$ ]]; then
            pop_question
            echo "返回上一个问题..."
            BACK_TO_PREV=1
            return 1
        fi
        
        if [[ "$answer" =~ ^[YyNn]$ ]]; then
            break
        else
            print_error "无效输入！请输入 y/n/r"
        fi
    done
    
    [[ "$answer" =~ ^[Yy]$ ]] && return 0 || return 2
}

is_root() { [[ $EUID -eq 0 ]]; }
has_sudo() { sudo -n true 2>/dev/null; }

run_cmd() {
    local cmd="$1"
    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
        cmd="${cmd//\/root\//\/home\/$TARGET_USER\/}"
    fi
    if ! is_root; then
        if [[ ! "$cmd" =~ ^sudo[[:space:]] ]]; then
            if [[ "$cmd" =~ ^(apt|apt-get|dpkg|systemctl|useradd|chpasswd|usermod|mkdir|cat|tee|rm|chmod|add-apt-repository|locale-gen|update-locale|curl|wget|dpkg) ]]; then
                cmd="sudo $cmd"
            fi
        fi
    else
        cmd="${cmd#sudo }"
    fi
    eval "$cmd"
    return $?
}

is_pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q ^ii; }
is_cmd_installed() { command -v "$1" >/dev/null 2>&1; }

check_lockfile() { 
    if [[ -f "$LOCKFILE" ]]; then
        return 0
    else
        return 1
    fi
}

# 读取锁文件（使用sed提高兼容性）
read_lockfile() {
    if [[ ! -f "$LOCKFILE" ]]; then
        return 1
    fi
    DESKTOP_TYPE=$(sed -n 's/.*"desktop": *"\([^"]*\)".*/\1/p' "$LOCKFILE")
    VNC_PORT=$(sed -n 's/.*"vnc_port": *\([0-9]*\).*/\1/p' "$LOCKFILE")
    VNC_PASSWORD=$(sed -n 's/.*"vnc_password": *"\([^"]*\)".*/\1/p' "$LOCKFILE")
    BROWSER_CHOICE=$(sed -n 's/.*"browser": *"\([^"]*\)".*/\1/p' "$LOCKFILE")
    INSTALL_NOVNC=$(sed -n 's/.*"novnc": *\([a-z]*\).*/\1/p' "$LOCKFILE")
}

generate_lockfile() {
    local install_time=$(date '+%Y-%m-%d %H:%M:%S')
    cat > "$LOCKFILE" <<EOF
{
    "install_time": "$install_time",
    "install_user": "$TARGET_USER",
    "desktop": "$DESKTOP_TYPE",
    "vnc_port": ${VNC_PORT:-null},
    "vnc_password": "${VNC_PASSWORD:-123456}",
    "browser": "${BROWSER_CHOICE:-none}",
    "common_software": ${INSTALL_COMMON_SOFT:-false},
    "language_pack": ${INSTALL_LANG:-false},
    "novnc": ${INSTALL_NOVNC:-false}
}
EOF
    chown "$TARGET_USER":"$TARGET_USER" "$LOCKFILE" 2>/dev/null || true
}

port_to_display() { echo $(($1 - 5900)); }

get_public_ip() {
    curl -s --max-time 2 ifconfig.me || curl -s --max-time 2 icanhazip.com || echo "无法获取公网IP"
}

# ========== 自动检测已有锁文件（始终提示选择） ==========
detect_existing_lockfile() {
    local locks=()
    if [[ -f "/root/vncinstall.lock" ]]; then
        locks+=("/root/vncinstall.lock")
    fi
    for user_home in /home/*; do
        if [[ -d "$user_home" && -f "$user_home/vncinstall.lock" ]]; then
            locks+=("$user_home/vncinstall.lock")
        fi
    done

    if [[ ${#locks[@]} -eq 0 ]]; then
        return
    fi

    print_warn "检测到安装记录:"
    local i=1
    for lock in "${locks[@]}"; do
        echo "  $i) $lock"
        ((i++))
    done
    echo "  0) 忽略，重新配置"
    read -p "请选择要使用的记录 [0-$((i-1))]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#locks[@]} )); then
        LOCKFILE="${locks[$((choice-1))]}"
        read_lockfile
        if [[ "$LOCKFILE" == "/root/vncinstall.lock" ]]; then
            TARGET_USER="root"
            TARGET_HOME="/root"
        else
            TARGET_USER=$(basename "$(dirname "$LOCKFILE")")
            TARGET_HOME="/home/$TARGET_USER"
        fi
        print_info "使用用户: $TARGET_USER"
    else
        print_info "忽略现有安装记录，将重新配置用户。"
        TARGET_USER=""
        TARGET_HOME=""
        LOCKFILE=""
    fi
}

# ========== 用户权限设置（若已指定用户则跳过） ==========
setup_user_permissions() {
    # 如果已经通过锁文件指定了用户，直接使用，不再交互
    if [[ -n "$TARGET_USER" ]]; then
        print_info "已指定用户: $TARGET_USER，跳过用户选择"
        if [[ -z "$TARGET_HOME" ]]; then
            if [[ "$TARGET_USER" == "root" ]]; then
                TARGET_HOME="/root"
            else
                TARGET_HOME="/home/$TARGET_USER"
            fi
        fi
        if [[ -z "$LOCKFILE" ]]; then
            LOCKFILE="$TARGET_HOME/vncinstall.lock"
        fi
        export TARGET_USER TARGET_HOME LOCKFILE
        return 0
    fi

    print_title "用户权限设置"
    reset_question_stack
    
    if is_root; then
        print_warn "当前是 root 用户，强烈建议使用普通用户运行桌面环境！"
        ask_yes_no "是否切换到普通用户" "switch_user"
        local res=$?
        if [[ $res -eq 1 ]]; then
            BACK_TO_PREV=0
            return 1
        elif [[ $res -eq 0 ]]; then
            while true; do
                new_user=$(ask_input "请输入要使用的用户名" "input_username" "")
                if [[ $? -eq 1 ]]; then
                    BACK_TO_PREV=0
                    continue
                fi
                
                if id "$new_user" &>/dev/null; then
                    print_warn "用户 $new_user 已存在。"
                    ask_yes_no "是否使用该用户" "use_exist_user"
                    local use_res=$?
                    if [[ $use_res -eq 1 ]]; then
                        BACK_TO_PREV=0
                        continue
                    elif [[ $use_res -eq 0 ]]; then
                        TARGET_USER="$new_user"
                        TARGET_HOME="/home/$new_user"
                        LOCKFILE="$TARGET_HOME/vncinstall.lock"
                        run_cmd "usermod -aG sudo $TARGET_USER"
                        print_success "已将 $TARGET_USER 添加到 sudo 组。"
                        break
                    fi
                else
                    while true; do
                        read -s -p "设置密码 (留空则默认 123456): " new_pass
                        echo
                        new_pass=${new_pass:-123456}
                        if [[ -z "$new_pass" ]]; then
                            print_error "密码不能为空，请重新输入！"
                            continue
                        fi
                        run_cmd "useradd -m -s /bin/bash $new_user"
                        echo "$new_user:$new_pass" | run_cmd "chpasswd"
                        run_cmd "usermod -aG sudo $new_user"
                        TARGET_USER="$new_user"
                        TARGET_HOME="/home/$new_user"
                        LOCKFILE="$TARGET_HOME/vncinstall.lock"
                        print_success "用户 $TARGET_USER 创建完成并已加入 sudo 组。"
                        break 2
                    done
                fi
            done
        else
            print_info "继续使用 root 用户安装。"
            TARGET_USER="root"
            TARGET_HOME="/root"
            LOCKFILE="/root/vncinstall.lock"
        fi
    else
        if has_sudo; then
            print_info "当前用户: $CURRENT_USER"
            ask_yes_no "是否使用当前用户 $CURRENT_USER 进行安装" "use_current_user"
            local res=$?
            if [[ $res -eq 1 ]]; then
                BACK_TO_PREV=0
                return 1
            elif [[ $res -eq 0 ]]; then
                TARGET_USER="$CURRENT_USER"
                TARGET_HOME="$HOME"
                LOCKFILE="$HOME/vncinstall.lock"
            else
                while true; do
                    new_user=$(ask_input "请输入要使用的用户名" "input_new_username" "")
                    if [[ $? -eq 1 ]]; then
                        BACK_TO_PREV=0
                        continue
                    fi
                    
                    if id "$new_user" &>/dev/null; then
                        print_warn "用户 $new_user 已存在。"
                        ask_yes_no "是否使用该用户" "use_exist_user2"
                        local use_res=$?
                        if [[ $use_res -eq 1 ]]; then
                            BACK_TO_PREV=0
                            continue
                        elif [[ $use_res -eq 0 ]]; then
                            TARGET_USER="$new_user"
                            TARGET_HOME="/home/$new_user"
                            LOCKFILE="$TARGET_HOME/vncinstall.lock"
                            run_cmd "usermod -aG sudo $TARGET_USER"
                            print_success "已将 $TARGET_USER 添加到 sudo 组。"
                            break
                        fi
                    else
                        while true; do
                            read -s -p "设置密码 (留空则默认 123456): " new_pass
                            echo
                            new_pass=${new_pass:-123456}
                            run_cmd "useradd -m -s /bin/bash $new_user"
                            echo "$new_user:$new_pass" | run_cmd "chpasswd"
                            run_cmd "usermod -aG sudo $new_user"
                            TARGET_USER="$new_user"
                            TARGET_HOME="/home/$new_user"
                            LOCKFILE="$TARGET_HOME/vncinstall.lock"
                            print_success "用户 $TARGET_USER 创建完成并已加入 sudo 组。"
                            break 2
                        done
                    fi
                done
            fi
        else
            print_error "当前用户无 sudo 权限，无法继续。"
            exit 1
        fi
    fi
    
    export TARGET_USER TARGET_HOME LOCKFILE
    return 0
}

# ========== 通用桌面快捷方式创建函数 ==========
create_app_desktop() {
    local app_name="$1"
    local source_desktop="$2"
    local target_name="$3"
    local desktop_dir="$TARGET_HOME/Desktop"
    
    if [[ -z "$target_name" ]]; then
        target_name=$(basename "$source_desktop")
    fi
    
    if [[ ! -f "$source_desktop" ]]; then
        print_warn "未找到 $app_name 的桌面文件: $source_desktop，跳过创建快捷方式"
        return
    fi
    
    # 确保桌面目录存在
    if [[ "$TARGET_USER" == "root" ]]; then
        mkdir -p "$desktop_dir"
    else
        sudo -u "$TARGET_USER" mkdir -p "$desktop_dir"
    fi
    
    local target_path="$desktop_dir/$target_name"
    if [[ "$TARGET_USER" == "root" ]]; then
        cp "$source_desktop" "$target_path" 2>/dev/null
    else
        sudo -u "$TARGET_USER" cp "$source_desktop" "$target_path" 2>/dev/null
    fi
    
    if [[ ! -f "$target_path" ]]; then
        print_error "复制 $app_name 桌面文件失败"
        return
    fi
    
    # 为 root 用户的浏览器类应用添加 --no-sandbox
    if [[ "$TARGET_USER" == "root" && "$app_name" =~ (Chrome|Edge|Firefox|Cursor) ]]; then
        sed -i '/^Exec=/ s/$/ --no-sandbox/' "$target_path"
        print_info "为 root 用户的 $app_name 添加 --no-sandbox 启动参数"
    fi
    
    chmod +x "$target_path"
    chown "$TARGET_USER":"$TARGET_USER" "$target_path" 2>/dev/null || true
    print_success "已创建 $app_name 桌面快捷方式"
}

# ========== 浏览器仓库管理 ==========
add_browser_repo() {
    local browser="$1"
    local keyring_dir="/etc/apt/keyrings"
    run_cmd "mkdir -p $keyring_dir"

    case "$browser" in
        google)
            print_info "添加 Google Chrome 仓库..."
            run_cmd "wget -q -O- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee $keyring_dir/google-chrome.gpg > /dev/null"
            run_cmd "echo 'deb [arch=amd64 signed-by=$keyring_dir/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main' | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null"
            run_cmd "apt update"
            ;;
        edge)
            print_info "添加 Microsoft Edge 仓库..."
            run_cmd "wget -q -O- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee $keyring_dir/microsoft-edge.gpg > /dev/null"
            run_cmd "echo 'deb [arch=amd64 signed-by=$keyring_dir/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main' | tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null"
            run_cmd "apt update"
            ;;
    esac
}

remove_browser_repo() {
    local browser="$1"
    case "$browser" in
        google)
            run_cmd "rm -f /etc/apt/sources.list.d/google-chrome.list"
            run_cmd "rm -f /etc/apt/keyrings/google-chrome.gpg"
            run_cmd "apt update"
            ;;
        edge)
            run_cmd "rm -f /etc/apt/sources.list.d/microsoft-edge.list"
            run_cmd "rm -f /etc/apt/keyrings/microsoft-edge.gpg"
            run_cmd "apt update"
            ;;
    esac
}

# ========== 浏览器安装 ==========
install_browser_google() {
    print_info "安装 Google Chrome..."
    add_browser_repo "google"
    run_cmd "apt install -y google-chrome-stable"
    create_app_desktop "Google Chrome" "/usr/share/applications/google-chrome.desktop"
}

install_browser_edge() {
    print_info "安装 Microsoft Edge..."
    add_browser_repo "edge"
    run_cmd "apt install -y microsoft-edge-stable"
    create_app_desktop "Microsoft Edge" "/usr/share/applications/microsoft-edge.desktop"
}

install_browser_firefox() {
    print_info "安装 Firefox ESR..."
    run_cmd "add-apt-repository -y ppa:mozillateam/ppa"
    run_cmd "apt update"
    run_cmd "apt install -y firefox-esr"
    # 优先使用 firefox-esr.desktop，若无则使用 firefox.desktop
    if [[ -f "/usr/share/applications/firefox-esr.desktop" ]]; then
        create_app_desktop "Firefox" "/usr/share/applications/firefox-esr.desktop" "firefox.desktop"
    else
        create_app_desktop "Firefox" "/usr/share/applications/firefox.desktop"
    fi
}

# ========== 基础安装 ==========
install_base() {
    print_info "更新系统并安装基础软件包..."
    run_cmd "DEBIAN_FRONTEND=noninteractive apt update"
    run_cmd "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
    run_cmd "apt install -y wget curl nano net-tools htop git ca-certificates software-properties-common"
}

install_desktop() {
    print_title "安装桌面环境: $DESKTOP_TYPE"
    case "$DESKTOP_TYPE" in
        xfce4)
            run_cmd "apt install -y xfce4 xfce4-goodies xfce4-terminal"
            DESKTOP_CMD="startxfce4"
            ;;
        xubuntu)
            run_cmd "apt install xubuntu-desktop -y"
            DESKTOP_CMD="startxfce4"
            ;;
        xfce-lite)
            run_cmd "apt install -y --no-install-recommends xfce4 xfce4-terminal"
            DESKTOP_CMD="startxfce4"
            ;;
        lxqt)
            run_cmd "add-apt-repository ppa:lxqt/stable -y"
            run_cmd "apt update"
            run_cmd "apt install lxqt -y"
            DESKTOP_CMD="startlxqt"
            ;;
        kde-full)
            run_cmd "apt install kde-full -y"
            DESKTOP_CMD="startkde"
            ;;
        kde-standard)
            run_cmd "apt install kde-standard -y"
            DESKTOP_CMD="startkde"
            ;;
        kde-plasma)
            run_cmd "apt install kde-plasma-desktop -y"
            DESKTOP_CMD="startkde"
            ;;
        mate-core)
            run_cmd "apt update && apt install mate-desktop-environment-core -y"
            DESKTOP_CMD="mate-session"
            ;;
        mate-full)
            run_cmd "apt install mate-desktop-environment-extras -y"
            DESKTOP_CMD="mate-session"
            ;;
        gnome-ubuntu)
            run_cmd "apt install ubuntu-gnome-desktop -y"
            DESKTOP_CMD="gnome-session"
            ;;
        gnome-core)
            run_cmd "apt install ubuntu-desktop -y"
            DESKTOP_CMD="gnome-session"
            ;;
    esac
    run_cmd "apt-get install -y dbus-x11"

    # 检测并选择可用的桌面启动命令（兼容不同发行版/版本）
    if command -v "$DESKTOP_CMD" >/dev/null 2>&1; then
        :
    else
        # KDE Plasma 可能有不同的启动命令
        if command -v startplasma-x11 >/dev/null 2>&1; then
            DESKTOP_CMD="startplasma-x11"
        elif command -v startplasma-wayland >/dev/null 2>&1; then
            DESKTOP_CMD="startplasma-wayland"
        elif command -v startkde >/dev/null 2>&1; then
            DESKTOP_CMD="startkde"
        elif command -v startlxqt >/dev/null 2>&1; then
            DESKTOP_CMD="startlxqt"
        elif command -v mate-session >/dev/null 2>&1; then
            DESKTOP_CMD="mate-session"
        elif command -v startxfce4 >/dev/null 2>&1; then
            DESKTOP_CMD="startxfce4"
        elif command -v gnome-session >/dev/null 2>&1; then
            DESKTOP_CMD="gnome-session"
        fi
    fi
}

# ========== 应用安装函数（附带快捷方式） ==========
install_qq() {
    print_info "安装 QQ..."
    local url="https://dldir1v6.qq.com/qqfile/qq/QQNT/Linux/QQ_3.2.25_260205_amd64_01.deb"
    local deb_file="/tmp/qq.deb"
    run_cmd "wget -O $deb_file $url"
    run_cmd "dpkg -i $deb_file"
    run_cmd "apt --fix-broken install -y"
    run_cmd "rm -f $deb_file"
    # 创建快捷方式
    if [[ -f "/usr/share/applications/qq.desktop" ]]; then
        create_app_desktop "QQ" "/usr/share/applications/qq.desktop"
    elif [[ -f "/usr/share/applications/QQ.desktop" ]]; then
        create_app_desktop "QQ" "/usr/share/applications/QQ.desktop"
    elif [[ -f "/usr/share/applications/qq.com-qq.desktop" ]]; then
        create_app_desktop "QQ" "/usr/share/applications/qq.com-qq.desktop"
    else
        print_warn "未找到 QQ 的桌面文件，跳过创建快捷方式"
    fi
    print_success "QQ 安装完成"
}

install_wechat() {
    print_info "安装 微信..."
    local url="https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb"
    local deb_file="/tmp/wechat.deb"
    run_cmd "wget -O $deb_file $url"
    run_cmd "dpkg -i $deb_file"
    run_cmd "apt --fix-broken install -y"
    run_cmd "rm -f $deb_file"
    # 创建快捷方式
    local desktop_path=""
    if [[ -f "/usr/share/applications/wechat.desktop" ]]; then
        desktop_path="/usr/share/applications/wechat.desktop"
    elif [[ -f "/usr/share/applications/electronic-wechat.desktop" ]]; then
        desktop_path="/usr/share/applications/electronic-wechat.desktop"
    fi

    if [[ -n "$desktop_path" ]]; then
        create_app_desktop "微信" "$desktop_path"
        # 从 .desktop 中提取 Exec 并创建 /usr/bin/wechat 启动脚本
        local exec_cmd
        exec_cmd=$(grep -m1 '^Exec=' "$desktop_path" | sed 's/^Exec=//; s/ %.\+//; s/ %U//; s/ %u//') || true
        if [[ -n "$exec_cmd" ]]; then
            cat > /usr/bin/wechat <<EOF
#!/bin/bash
exec $exec_cmd "\$@"
EOF
            chmod +x /usr/bin/wechat
            print_info "已创建 /usr/bin/wechat 启动脚本"
        fi
    else
        print_warn "未找到微信的桌面文件，跳过创建快捷方式和 /usr/bin/wechat"
    fi
    print_success "微信 安装完成"
}

install_finalshell() {
    print_info "安装 FinalShell..."
    local url="https://dl.hostbuf.com/finalshell3/finalshell_linux_x64.deb"
    local deb_file="/tmp/finalshell.deb"
    run_cmd "wget -O $deb_file $url"
    run_cmd "dpkg -i $deb_file"
    run_cmd "apt --fix-broken install -y"
    run_cmd "rm -f $deb_file"
    # 创建快捷方式
    if [[ -f "/usr/share/applications/finalshell.desktop" ]]; then
        create_app_desktop "FinalShell" "/usr/share/applications/finalshell.desktop"
    else
        print_warn "未找到 FinalShell 的桌面文件，跳过创建快捷方式"
    fi

    # 如果安装目录存在，创建 /usr/bin/FinalShell 快捷脚本
    if [[ -x "/usr/lib/finalshell/bin/FinalShell" ]]; then
        cat > /usr/bin/FinalShell <<'EOF'
#!/bin/bash
exec /usr/lib/finalshell/bin/FinalShell "$@"
EOF
        chmod +x /usr/bin/FinalShell
        print_info "已创建 /usr/bin/FinalShell 启动脚本"
    fi
    print_success "FinalShell 安装完成"
}

install_cursor() {
    print_info "安装 Cursor 编辑器..."
    run_cmd "curl -fsSL https://downloads.cursor.com/keys/anysphere.asc | gpg --dearmor | tee /etc/apt/keyrings/cursor.gpg > /dev/null"
    run_cmd "echo 'deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main' | tee /etc/apt/sources.list.d/cursor.list > /dev/null"
    run_cmd "apt update"
    run_cmd "apt install -y cursor"
    # 创建快捷方式
    if [[ -f "/usr/share/applications/cursor.desktop" ]]; then
        create_app_desktop "Cursor" "/usr/share/applications/cursor.desktop"
    else
        print_warn "未找到 Cursor 的桌面文件，跳过创建快捷方式"
    fi
    print_success "Cursor 安装完成"
}

install_realvnc_viewer() {
    print_info "安装 RealVNC Viewer..."
    local url="https://downloads.realvnc.com/download/file/viewer.files/VNC-Viewer-7.15.1-Linux-x64.deb"
    local deb_file="/tmp/realvnc-viewer.deb"
    run_cmd "wget -O $deb_file $url"
    run_cmd "dpkg -i $deb_file"
    run_cmd "apt --fix-broken install -y"
    run_cmd "rm -f $deb_file"
    # 创建快捷方式
    if [[ -f "/usr/share/applications/realvnc-vncviewer.desktop" ]]; then
        create_app_desktop "RealVNC Viewer" "/usr/share/applications/realvnc-vncviewer.desktop"
    elif [[ -f "/usr/share/applications/vncviewer.desktop" ]]; then
        create_app_desktop "RealVNC Viewer" "/usr/share/applications/vncviewer.desktop"
    else
        print_warn "未找到 RealVNC Viewer 的桌面文件，跳过创建快捷方式"
    fi
    print_success "RealVNC Viewer 安装完成"
}

install_ibus() {
    print_info "安装 IBus 输入法..."
    run_cmd "apt update"
    run_cmd "apt install -y ibus ibus-pinyin"
    
    if ! locale -a | grep -q zh_CN.utf8; then
        run_cmd "apt install -y language-pack-zh-hans"
    fi
    run_cmd "update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8"
    run_cmd "im-config -s ibus"
    
    local profile_file="$TARGET_HOME/.xprofile"
    if [[ ! -f "$profile_file" ]]; then
        profile_file="$TARGET_HOME/.profile"
    fi
    if ! grep -q "ibus-daemon" "$profile_file" 2>/dev/null; then
        echo '' >> "$profile_file"
        echo '# 自动启动 IBus 输入法' >> "$profile_file"
        echo 'export GTK_IM_MODULE=ibus' >> "$profile_file"
        echo 'export QT_IM_MODULE=ibus' >> "$profile_file"
        echo 'export XMODIFIERS=@im=ibus' >> "$profile_file"
        echo 'ibus-daemon -drx' >> "$profile_file"
    fi
    
    # 配置中文环境变量到用户bashrc
    configure_chinese_locale_for_user
    
    print_success "IBus 安装完成"
}

install_fcitx5() {
    print_info "安装 Fcitx5 中文输入法..."
    run_cmd "apt install -y fcitx5 fcitx5-chinese-addons fcitx5-config-qt"
    
    # 配置中文环境变量到用户bashrc
    configure_chinese_locale_for_user
    
    print_success "Fcitx5 安装完成"
}

configure_chinese_locale_for_user() {
    local profile_file="$TARGET_HOME/.bashrc"
    if [[ ! -f "$profile_file" ]]; then
        if [[ "$TARGET_USER" == "root" ]]; then
            touch "$profile_file"
        else
            sudo -u "$TARGET_USER" touch "$profile_file"
        fi
    fi
    if ! grep -q "export LANG=zh_CN.UTF-8" "$profile_file" 2>/dev/null; then
        echo -e "\n# Chinese locale settings" >> "$profile_file"
        echo "export LANG=zh_CN.UTF-8" >> "$profile_file"
        echo "export LANGUAGE=zh_CN.UTF-8" >> "$profile_file"
        echo "export LC_ALL=zh_CN.UTF-8" >> "$profile_file"
        chown "$TARGET_USER":"$TARGET_USER" "$profile_file" 2>/dev/null || true
        print_info "已为用户 $TARGET_USER 配置中文环境变量"
    fi
}

install_vscode() {
    print_info "安装 Visual Studio Code..."
    run_cmd "wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg"
    run_cmd "install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/"
    run_cmd "sh -c 'echo \"deb [arch=amd64] https://packages.microsoft.com/repos/code stable main\" > /etc/apt/sources.list.d/vscode.list'"
    run_cmd "rm -f packages.microsoft.gpg"
    run_cmd "apt update"
    run_cmd "apt install -y code"
    create_app_desktop "Visual Studio Code" "/usr/share/applications/code.desktop"
}

install_vlc() { 
    run_cmd "apt install -y vlc"
    create_app_desktop "VLC" "/usr/share/applications/vlc.desktop"
}
install_mpv() { 
    run_cmd "apt install -y mpv"
    create_app_desktop "MPV" "/usr/share/applications/mpv.desktop"
}
install_libreoffice() { 
    run_cmd "apt install -y libreoffice"
    create_app_desktop "LibreOffice" "/usr/share/applications/libreoffice-startcenter.desktop" "libreoffice.desktop"
}
install_flameshot() { 
    run_cmd "apt install -y flameshot"
    create_app_desktop "Flameshot" "/usr/share/applications/org.flameshot.Flameshot.desktop" "flameshot.desktop"
}
install_compression_tools() { run_cmd "apt install -y p7zip-full unrar"; }
install_sys_tools() { run_cmd "apt install -y neofetch htop tmux"; }
install_common_soft() {
    run_cmd "apt install -y gedit mousepad ristretto"
    run_cmd "apt install -y gnome-disk-utility gnome-system-monitor"
    # 为这些轻量应用创建快捷方式（如果存在）
    [[ -f "/usr/share/applications/gedit.desktop" ]] && create_app_desktop "Gedit" "/usr/share/applications/gedit.desktop"
    [[ -f "/usr/share/applications/mousepad.desktop" ]] && create_app_desktop "Mousepad" "/usr/share/applications/mousepad.desktop"
    [[ -f "/usr/share/applications/ristretto.desktop" ]] && create_app_desktop "Ristretto" "/usr/share/applications/ristretto.desktop"
    [[ -f "/usr/share/applications/gnome-disk-utility.desktop" ]] && create_app_desktop "磁盘工具" "/usr/share/applications/gnome-disk-utility.desktop"
    [[ -f "/usr/share/applications/gnome-system-monitor.desktop" ]] && create_app_desktop "系统监视器" "/usr/share/applications/gnome-system-monitor.desktop"
}

# ========== VNC 安装 ==========
install_vnc() {
    print_title "安装 TigerVNC"
    run_cmd "apt install -y tigervnc-standalone-server tigervnc-xorg-extension"
    run_cmd "mkdir -p $TARGET_HOME/.vnc/"
    
    local xstartup_path="$TARGET_HOME/.vnc/xstartup"
    run_cmd "touch $xstartup_path"
    # 根据所选输入法和桌面选择生成 xstartup
    # SELECTED_INPUT_METHOD 可能由高级安装流程设置（fcitx5 或 ibus），默认为 fcitx5
    local im_choice="${SELECTED_INPUT_METHOD:-fcitx5}"

    # 选择可用桌面启动命令
    local start_cmd="${DESKTOP_CMD:-}"
    if [[ -z "$start_cmd" ]]; then
        if command -v startxfce4 >/dev/null 2>&1; then
            start_cmd="startxfce4"
        elif command -v startplasma-x11 >/dev/null 2>&1; then
            start_cmd="startplasma-x11"
        elif command -v startkde >/dev/null 2>&1; then
            start_cmd="startkde"
        elif command -v mate-session >/dev/null 2>&1; then
            start_cmd="mate-session"
        elif command -v startlxqt >/dev/null 2>&1; then
            start_cmd="startlxqt"
        elif command -v gnome-session >/dev/null 2>&1; then
            start_cmd="gnome-session"
        else
            start_cmd="startxfce4"
        fi
    fi

    if [[ "$im_choice" == "ibus" ]]; then
        cat > /tmp/xstartup.tmp <<EOF
#!/bin/bash
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export INPUT_METHOD=ibus
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS="@im=ibus"
ibus-daemon -drx
xset s off
xset -dpms
xset s noblank
exec $start_cmd
EOF
    else
        cat > /tmp/xstartup.tmp <<EOF
#!/bin/bash
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export INPUT_METHOD=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS="@im=fcitx5"
fcitx5 &
xset s off
xset -dpms
xset s noblank
exec $start_cmd
EOF
    fi
    if is_root || [[ "$TARGET_USER" == "root" ]]; then
        cp /tmp/xstartup.tmp "$xstartup_path"
    else
        sudo -u "$TARGET_USER" cp /tmp/xstartup.tmp "$xstartup_path"
    fi
    rm /tmp/xstartup.tmp
    run_cmd "chmod +x $xstartup_path"
    run_cmd "chown -R $TARGET_USER:$TARGET_USER $TARGET_HOME/.vnc/"
    
    # 设置 VNC 密码（直接以目标用户身份执行）
    if [[ -n "$VNC_PASSWORD" ]]; then
        print_info "设置 VNC 密码..."
        if [[ "$TARGET_USER" == "root" ]]; then
            printf "%s\n%s\nn\n" "$VNC_PASSWORD" "$VNC_PASSWORD" | vncpasswd >/dev/null 2>&1
        else
            runuser -l "$TARGET_USER" -c "printf '%s\n%s\nn\n' \"$VNC_PASSWORD\" \"$VNC_PASSWORD\" | vncpasswd >/dev/null 2>&1"
        fi
    fi
    
    local display_num=$(port_to_display $VNC_PORT)
    local service_name="vncserver@$display_num.service"
    
    cat > /tmp/vncserver.service.tmp <<EOF
[Unit]
Description=Remote desktop service (VNC)
After=syslog.target network.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$TARGET_HOME
ExecStart=/usr/bin/vncserver :$display_num -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -ZlibLevel $VNC_ZLIB -localhost $VNC_LOCALHOST -fg
ExecStop=/usr/bin/vncserver -kill :$display_num
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    if is_root; then
        cp /tmp/vncserver.service.tmp "/etc/systemd/system/$service_name"
    else
        sudo cp /tmp/vncserver.service.tmp "/etc/systemd/system/$service_name"
    fi
    rm /tmp/vncserver.service.tmp
    
    run_cmd "systemctl daemon-reload"
    run_cmd "systemctl enable $service_name"
    
    if [[ "$VNC_START_NOW" == "y" ]]; then
        run_cmd "systemctl start $service_name"
    fi
}

install_language() {
    print_info "安装中文语言包及字体..."
    run_cmd "apt install -y language-pack-zh-hans language-pack-zh-hans-base"
    run_cmd "apt install -y fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk"
    run_cmd "locale-gen zh_CN.UTF-8"
    run_cmd "update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8"
    cat > /tmp/locale.tmp <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_NUMERIC="zh_CN.UTF-8"
LC_TIME="zh_CN.UTF-8"
LC_MONETARY="zh_CN.UTF-8"
LC_PAPER="zh_CN.UTF-8"
LC_NAME="zh_CN.UTF-8"
LC_ADDRESS="zh_CN.UTF-8"
LC_TELEPHONE="zh_CN.UTF-8"
LC_MEASUREMENT="zh_CN.UTF-8"
LC_IDENTIFICATION="zh_CN.UTF-8"
EOF
    if is_root; then
        cp /tmp/locale.tmp /etc/default/locale
    else
        sudo cp /tmp/locale.tmp /etc/default/locale
    fi
    rm /tmp/locale.tmp
}

# ========== noVNC 安装（支持自定义端口） ==========
install_novnc() {
    print_info "安装 noVNC..."
    local display_num=$(port_to_display $VNC_PORT)
    local novnc_port=${NOVNC_PORT:-6080}
    local cmd="bash <(curl -L https://raw.githubusercontent.com/fanchuanhah/auto-install-desktop-and-vnc-and-set-enable/refs/heads/main/novnc/install.sh) -auto -vncport=$VNC_PORT -novncport=$novnc_port"
    run_cmd "$cmd" || print_warn "noVNC 安装脚本执行失败"
    run_cmd "systemctl restart vncserver@$display_num.service"
}

install_all_apps() {
    print_title "一键安装全部应用"
    echo "即将安装: QQ、微信、FinalShell、Cursor、RealVNC Viewer、IBus、VSCode、VLC、MPV、LibreOffice、Flameshot"
    
    confirm_action "确认安装全部应用" "confirm_install_all"
    local res=$?
    if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
        return
    fi
    
    install_qq
    install_wechat
    install_finalshell
    install_cursor
    install_realvnc_viewer
    install_ibus
    install_vscode
    install_vlc
    install_mpv
    install_libreoffice
    install_flameshot
    
    print_success "全部应用安装完成！"
    read -p "按回车键返回主菜单..." -r
}

uninstall_all_apps() {
    print_title "一键卸载全部应用"
    
    confirm_action "确认卸载全部应用" "confirm_uninstall_all"
    local res1=$?
    if [[ $res1 -eq 1 ]] || [[ $res1 -eq 2 ]]; then
        return
    fi
    
    confirm_action "最后确认" "confirm_uninstall_all_final"
    local res2=$?
    if [[ $res2 -eq 1 ]] || [[ $res2 -eq 2 ]]; then
        return
    fi
    
    run_cmd "dpkg -r qq 2>/dev/null || true"
    run_cmd "dpkg -r wechat 2>/dev/null || true"
    run_cmd "dpkg -r finalshell 2>/dev/null || true"
    run_cmd "apt remove -y cursor 2>/dev/null || true"
    run_cmd "dpkg -r realvnc-vnc-viewer 2>/dev/null || true"
    run_cmd "apt remove -y ibus* 2>/dev/null || true"
    run_cmd "apt remove -y fcitx5* 2>/dev/null || true"
    run_cmd "apt remove -y code vlc mpv libreoffice* flameshot 2>/dev/null || true"
    
    run_cmd "rm -f /etc/apt/sources.list.d/cursor.list"
    run_cmd "rm -f /etc/apt/keyrings/cursor.gpg"
    run_cmd "rm -f /etc/apt/sources.list.d/vscode.list"
    run_cmd "rm -f packages.microsoft.gpg"
    
    run_cmd "apt autoremove -y"
    run_cmd "apt update"
    
    print_success "全部应用卸载完成！"
    read -p "按回车键返回主菜单..." -r
}

# ========== 独立应用安装菜单 ==========
install_apps_menu() {
    print_title "独立应用安装"

    # 如果未指定目标用户，尝试检测或让用户选择
    if [[ -z "$TARGET_USER" ]]; then
        print_warn "未指定目标用户，请选择要安装应用的用户。"
        local users=($(awk -F: '$3>=1000 && $1!="nobody" {print $1}' /etc/passwd))
        if [[ ${#users[@]} -gt 0 ]]; then
            echo "可用的普通用户:"
            for i in "${!users[@]}"; do
                echo "  $((i+1))) ${users[$i]}"
            done
            echo "  $(( ${#users[@]}+1 ))) root"
            read -p "请选择 [1-$(( ${#users[@]}+1 ))]: " user_choice
            if [[ "$user_choice" =~ ^[0-9]+$ ]] && (( user_choice >= 1 && user_choice <= ${#users[@]} )); then
                TARGET_USER="${users[$((user_choice-1))]}"
                TARGET_HOME="/home/$TARGET_USER"
            elif [[ "$user_choice" == $(( ${#users[@]}+1 )) ]]; then
                TARGET_USER="root"
                TARGET_HOME="/root"
            else
                print_error "无效选择"
                return
            fi
        else
            read -p "请输入用户名: " TARGET_USER
            if id "$TARGET_USER" &>/dev/null; then
                TARGET_HOME=$(eval echo ~$TARGET_USER)
            else
                print_error "用户不存在"
                return
            fi
        fi
        LOCKFILE="$TARGET_HOME/vncinstall.lock"
        print_info "将使用用户: $TARGET_USER"
    fi

    echo "请选择要安装的应用（可多选，输入序号用空格分隔）:"
    echo "  1) Firefox"
    echo "  2) Microsoft Edge"
    echo "  3) Google Chrome"
    echo "  4) Fcitx5 输入法"
    echo "  5) Visual Studio Code"
    echo "  6) VLC 播放器"
    echo "  7) MPV 播放器"
    echo "  8) LibreOffice"
    echo "  9) Flameshot"
    echo " 10) 压缩工具"
    echo " 11) 系统工具"
    echo " 12) QQ"
    echo " 13) 微信"
    echo " 14) FinalShell"
    echo " 15) Cursor"
    echo " 16) RealVNC Viewer"
    echo " 17) IBus"
    echo "  0) 返回主菜单"
    echo
    
    app_choices=$(ask_input "请输入序号" "select_apps" "")
    local res=$?
    if [[ $res -eq 1 ]]; then
        BACK_TO_PREV=0
        return
    fi
    
    if [[ -z "$app_choices" || "$app_choices" == "0" ]]; then
        return
    fi
    
    for choice in $app_choices; do
        case $choice in
            1) install_browser_firefox ;;
            2) install_browser_edge ;;
            3) install_browser_google ;;
            4) install_fcitx5 ;;
            5) install_vscode ;;
            6) install_vlc ;;
            7) install_mpv ;;
            8) install_libreoffice ;;
            9) install_flameshot ;;
            10) install_compression_tools ;;
            11) install_sys_tools ;;
            12) install_qq ;;
            13) install_wechat ;;
            14) install_finalshell ;;
            15) install_cursor ;;
            16) install_realvnc_viewer ;;
            17) install_ibus ;;
        esac
    done
    
    print_success "应用安装流程结束。"
    read -p "按回车键返回主菜单..." -r
}

# ========== 应用批量管理菜单 ==========
app_batch_menu() {
    print_title "应用批量管理"
    echo "1) 安装全部应用"
    echo "2) 卸载全部应用"
    echo "0) 返回主菜单"
    read -p "请选择 [0-2]: " batch_choice
    case $batch_choice in
        1) install_all_apps ;;
        2) uninstall_all_apps ;;
        0) return ;;
        *) print_error "无效选择"; sleep 1 ;;
    esac
}

# ========== 自动安装（简化版，强制 root，自动重启） ==========
auto_install() {
    print_title "自动安装模式"
    reset_question_stack

    # 强制使用 root 用户
    TARGET_USER="root"
    TARGET_HOME="/root"
    LOCKFILE="/root/vncinstall.lock"
    export TARGET_USER TARGET_HOME LOCKFILE

    # 检查锁文件并询问（仅一次确认）
    if check_lockfile; then
        print_warn "检测到锁文件，系统可能已安装过桌面环境。"
        confirm_action "是否继续安装（将覆盖原有配置）" "confirm_auto_install"
        local res=$?
        if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
            print_info "已取消安装。"
            return
        fi
    else
        confirm_action "确认执行自动安装" "confirm_auto_install_final"
        local res=$?
        if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
            print_info "已取消安装。"
            return
        fi
    fi

    DESKTOP_TYPE="$AUTO_DESKTOP_TYPE"
    BROWSER_CHOICE="$AUTO_BROWSER_CHOICE"
    INSTALL_COMMON_SOFT="$AUTO_INSTALL_COMMON_SOFT"
    INSTALL_VNC="$AUTO_INSTALL_VNC"
    VNC_PORT="$AUTO_VNC_PORT"
    VNC_GEOMETRY="$AUTO_VNC_GEOMETRY"
    VNC_DEPTH="$AUTO_VNC_DEPTH"
    VNC_ZLIB="$AUTO_VNC_ZLIB"
    VNC_LOCALHOST="$AUTO_VNC_LOCALHOST"
    VNC_PASSWORD="$AUTO_VNC_PASSWORD"
    VNC_START_NOW="$AUTO_VNC_START_NOW"
    INSTALL_LANG="$AUTO_INSTALL_LANG"
    INSTALL_NOVNC="$AUTO_INSTALL_NOVNC"
    NOVNC_PORT="$AUTO_NOVNC_PORT"

    install_base
    install_desktop
    [[ "$BROWSER_CHOICE" != "none" ]] && {
        case $BROWSER_CHOICE in
            firefox) install_browser_firefox ;;
            edge) install_browser_edge ;;
            google) install_browser_google ;;
        esac
    }
    [[ "$INSTALL_COMMON_SOFT" == "y" ]] && install_common_soft
    [[ "$INSTALL_VNC" == "y" ]] && install_vnc
    [[ "$INSTALL_LANG" == "y" ]] && install_language
    [[ "$INSTALL_NOVNC" == "y" ]] && install_novnc

    generate_lockfile
    auto_install_summary
}

auto_install_summary() {
    print_title "安装完成信息汇总"
    echo -e "${GREEN}[成功] 安装完成！${NC}"
    echo -e "${CYAN}[信息] 安装用户:${NC} $TARGET_USER"
    echo -e "${CYAN}[信息] 桌面环境:${NC} $DESKTOP_TYPE"
    
    if [[ "$INSTALL_VNC" == "y" ]]; then
        local public_ip=$(get_public_ip)
        echo -e "${CYAN}[信息] VNC 地址:${NC} $public_ip:$VNC_PORT"
        echo -e "${CYAN}[信息] VNC 密码:${NC} ${VNC_PASSWORD}"
    fi
    
    if [[ "$INSTALL_NOVNC" == "y" ]]; then
        local public_ip=$(get_public_ip)
        echo -e "${CYAN}[信息] noVNC 地址:${NC} http://$public_ip:$NOVNC_PORT/vnc.html"
    fi
    
    if [[ "$BROWSER_CHOICE" != "none" ]]; then
        echo -e "${CYAN}[信息] 浏览器:${NC} $BROWSER_CHOICE"
    fi
    
    echo
    print_warn "系统将在 10 秒后重启..."
    sleep 10
    run_cmd "reboot"
}

# ========== 高级安装 ==========
advanced_install() {
    print_title "高级安装模式"
    reset_question_stack
    declare -a STATE_STACK=()

    if check_lockfile; then
        print_warn "检测到锁文件，系统可能已安装过桌面环境。"
        confirm_action "是否继续安装" "confirm_adv_install"
        local res=$?
        if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
            print_info "已取消安装。"
            return
        fi
    fi

    confirm_action "确认开始高级安装流程" "confirm_adv_install_final"
    local res=$?
    if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
        print_info "已取消安装。"
        return
    fi

    local current_state="user_permissions"
    STATE_STACK+=("$current_state")

    while true; do
        if [[ $BACK_TO_PREV -eq 1 ]]; then
            BACK_TO_PREV=0
            if [[ ${#STATE_STACK[@]} -gt 1 ]]; then
                unset 'STATE_STACK[-1]'
                current_state="${STATE_STACK[-1]}"
                reset_question_stack
                continue
            else
                print_info "已返回主菜单。"
                return
            fi
        fi

        case $current_state in
            "user_permissions")
                setup_user_permissions
                if [[ $? -eq 1 ]]; then
                    return
                fi
                current_state="select_desktop"
                STATE_STACK+=("$current_state")
                ;;
                
            "select_desktop")
                echo "请选择要安装的桌面环境:"
                echo "  1) XFCE 完整版"
                echo "  2) Xubuntu"
                echo "  3) XFCE 精简版"
                echo "  4) LXQt"
                echo "  5) KDE Plasma 完整版"
                echo "  6) KDE Plasma 标准版"
                echo "  7) KDE Plasma 最小版"
                echo "  8) MATE 最小版"
                echo "  9) MATE 完整版"
                echo " 10) GNOME Ubuntu 定制版"
                echo " 11) GNOME 标准版"
                
                desktop_choice=$(ask_input "请输入数字 (1-11)" "select_desktop" "1")
                if [[ $? -eq 1 ]]; then
                    continue
                fi
                desktop_choice=${desktop_choice:-1}
                
                case $desktop_choice in
                    1) DESKTOP_TYPE="xfce4" ;;
                    2) DESKTOP_TYPE="xubuntu" ;;
                    3) DESKTOP_TYPE="xfce-lite" ;;
                    4) DESKTOP_TYPE="lxqt" ;;
                    5) DESKTOP_TYPE="kde-full" ;;
                    6) DESKTOP_TYPE="kde-standard" ;;
                    7) DESKTOP_TYPE="kde-plasma" ;;
                    8) DESKTOP_TYPE="mate-core" ;;
                    9) DESKTOP_TYPE="mate-full" ;;
                    10) DESKTOP_TYPE="gnome-ubuntu" ;;
                    11) DESKTOP_TYPE="gnome-core" ;;
                esac
                current_state="browser_choice"
                STATE_STACK+=("$current_state")
                ;;
                
            "browser_choice")
                ask_yes_no "是否安装浏览器" "install_browser"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    echo "请选择浏览器:"
                    echo "  1) Firefox"
                    echo "  2) Microsoft Edge"
                    echo "  3) Google Chrome"
                    
                    browser_choice=$(ask_input "请输入数字 (1-3)" "select_browser" "1")
                    if [[ $? -eq 1 ]]; then
                        continue
                    fi
                    browser_choice=${browser_choice:-1}
                    
                    case $browser_choice in
                        1) BROWSER_CHOICE="firefox" ;;
                        2) BROWSER_CHOICE="edge" ;;
                        3) BROWSER_CHOICE="google" ;;
                    esac
                else
                    BROWSER_CHOICE="none"
                fi
                current_state="common_soft"
                STATE_STACK+=("$current_state")
                ;;
                
                
                
            "common_soft")
                ask_yes_no "是否安装常用软件" "install_common_soft"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    INSTALL_COMMON_SOFT="y"
                else
                    INSTALL_COMMON_SOFT="n"
                fi
                current_state="vnc_install"
                STATE_STACK+=("$current_state")
                ;;
                
            "vnc_install")
                ask_yes_no "是否安装 TigerVNC" "install_vnc"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    INSTALL_VNC="y"
                    current_state="vnc_config"
                else
                    INSTALL_VNC="n"
                    current_state="language_install"
                fi
                STATE_STACK+=("$current_state")
                ;;
                
            "vnc_config")
                ask_yes_no "是否使用默认 VNC 配置" "vnc_default_config"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    VNC_PORT="5901"
                    VNC_GEOMETRY="1280x800"
                    VNC_DEPTH="16"
                    VNC_ZLIB="9"
                    VNC_LOCALHOST="no"
                    current_state="vnc_password"
                else
                    while true; do
                        VNC_PORT=$(ask_input "请输入 VNC 端口 (5901-5910)" "vnc_port" "")
                        if [[ $? -eq 1 ]]; then
                            continue 2
                        fi
                        if [[ "$VNC_PORT" =~ ^59[0-1][0-9]$ ]] && [ "$VNC_PORT" -ge 5901 ] && [ "$VNC_PORT" -le 5910 ]; then
                            break
                        else
                            print_error "端口范围 5901~5910"
                        fi
                    done
                    
                    VNC_GEOMETRY=$(ask_input "请输入分辨率" "vnc_geometry" "1280x800")
                    if [[ $? -eq 1 ]]; then
                        continue
                    fi
                    VNC_GEOMETRY=${VNC_GEOMETRY:-1280x800}
                    
                    VNC_DEPTH=$(ask_input "请输入色彩深度" "vnc_depth" "16")
                    if [[ $? -eq 1 ]]; then
                        continue
                    fi
                    VNC_DEPTH=${VNC_DEPTH:-16}
                    
                    VNC_ZLIB=$(ask_input "请输入压缩级别 (0-9)" "vnc_zlib" "9")
                    if [[ $? -eq 1 ]]; then
                        continue
                    fi
                    VNC_ZLIB=${VNC_ZLIB:-9}
                    
                    VNC_LOCALHOST=$(ask_input "是否仅本地访问 (yes/no)" "vnc_localhost" "no")
                    if [[ $? -eq 1 ]]; then
                        continue
                    fi
                    VNC_LOCALHOST=${VNC_LOCALHOST:-no}
                    
                    current_state="vnc_password"
                fi
                STATE_STACK+=("$current_state")
                ;;
                
            "vnc_password")
                while true; do
                    read -s -p "请输入 VNC 密码 (留空则使用 123456): " vnc_pass_input
                    echo
                    if [[ "$vnc_pass_input" =~ ^[Rr]$ ]]; then
                        BACK_TO_PREV=1
                        continue 2
                    fi
                    if [[ -z "$vnc_pass_input" ]]; then
                        VNC_PASSWORD="123456"
                    else
                        VNC_PASSWORD="$vnc_pass_input"
                    fi
                    break
                done
                current_state="vnc_start"
                STATE_STACK+=("$current_state")
                ;;
                
            "vnc_start")
                ask_yes_no "是否立即启动 VNC 服务" "vnc_start_now"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    VNC_START_NOW="y"
                else
                    VNC_START_NOW="n"
                fi
                current_state="language_install"
                STATE_STACK+=("$current_state")
                ;;
                
            "language_install")
                ask_yes_no "是否安装中文语言包及字体" "install_lang"
                local res=$?
                if [[ $res -eq 1 ]]; then
                    continue
                elif [[ $res -eq 0 ]]; then
                    INSTALL_LANG="y"
                else
                    INSTALL_LANG="n"
                fi
                # 询问中文输入法（放在语言包询问之后）
                current_state="input_method_choice"
                STATE_STACK+=("$current_state")
                ;;

            "input_method_choice")
                echo "是否安装中文输入法？"
                echo " 1) 安装 Fcitx5 (推荐)"
                echo " 2) 安装 IBus"
                echo " 3) 不安装"
                im_choice=$(ask_input "请输入数字 (1-3)" "select_input_method" "1")
                if [[ $? -eq 1 ]]; then
                    continue
                fi
                case "$im_choice" in
                    1)
                        INSTALL_INPUT_METHOD="y"
                        INPUT_METHOD_TYPE="fcitx5"
                        ;;
                    2)
                        INSTALL_INPUT_METHOD="y"
                        INPUT_METHOD_TYPE="ibus"
                        ;;
                    *)
                        INSTALL_INPUT_METHOD="n"
                        INPUT_METHOD_TYPE=""
                        ;;
                esac
                current_state="novnc_install"
                STATE_STACK+=("$current_state")
                ;;
                
            "novnc_install")
                if [[ "$INSTALL_VNC" == "y" ]]; then
                    ask_yes_no "是否安装 noVNC" "install_novnc"
                    local res=$?
                    if [[ $res -eq 1 ]]; then
                        continue
                    elif [[ $res -eq 0 ]]; then
                        INSTALL_NOVNC="y"
                        # 高级安装中 noVNC 端口使用默认 6080，暂不提供自定义
                        NOVNC_PORT="${NOVNC_PORT:-6080}"
                    else
                        INSTALL_NOVNC="n"
                    fi
                else
                    INSTALL_NOVNC="n"
                fi
                current_state="execute_install"
                STATE_STACK+=("$current_state")
                ;;
                
            "execute_install")
                install_base
                install_desktop
                [[ "$BROWSER_CHOICE" != "none" ]] && {
                    case $BROWSER_CHOICE in
                        firefox) install_browser_firefox ;;
                        edge) install_browser_edge ;;
                        google) install_browser_google ;;
                    esac
                }
                if [[ "$INSTALL_INPUT_METHOD" == "y" ]]; then
                    if [[ "$INPUT_METHOD_TYPE" == "ibus" ]]; then
                        install_ibus
                    else
                        install_fcitx5
                    fi
                fi
                [[ "$INSTALL_COMMON_SOFT" == "y" ]] && install_common_soft
                # 在启动 VNC 前，将选择的输入法传递给 VNC xstartup 生成逻辑
                if [[ "$INSTALL_VNC" == "y" ]]; then
                    SELECTED_INPUT_METHOD="${INPUT_METHOD_TYPE:-fcitx5}"
                    install_vnc
                fi
                [[ "$INSTALL_LANG" == "y" ]] && install_language
                [[ "$INSTALL_NOVNC" == "y" ]] && install_novnc
                
                generate_lockfile
                show_install_summary
                return
                ;;
        esac
    done
}

# ========== 普通安装总结 ==========
show_install_summary() {
    print_title "安装完成信息汇总"
    echo -e "${GREEN}[成功] 安装完成！${NC}"
    echo -e "${CYAN}[信息] 安装用户:${NC} $TARGET_USER"
    echo -e "${CYAN}[信息] 桌面环境:${NC} $DESKTOP_TYPE"
    
    if [[ "$INSTALL_VNC" == "y" ]]; then
        local public_ip=$(get_public_ip)
        echo -e "${CYAN}[信息] VNC 地址:${NC} $public_ip:$VNC_PORT"
        echo -e "${CYAN}[信息] VNC 密码:${NC} ${VNC_PASSWORD}"
        echo -e "${YELLOW}[注意] VNC 密码保存在锁文件中，关闭SSH后仍可使用${NC}"
    fi
    
    if [[ "$INSTALL_NOVNC" == "y" ]]; then
        local public_ip=$(get_public_ip)
        echo -e "${CYAN}[信息] noVNC 地址:${NC} http://$public_ip:${NOVNC_PORT:-6080}/vnc.html"
    fi
    
    if [[ "$BROWSER_CHOICE" != "none" ]]; then
        echo -e "${CYAN}[信息] 浏览器:${NC} $BROWSER_CHOICE"
    fi
    
    echo
    echo -e "${WHITE}请选择后续操作:${NC}"
    echo "  1) 立即重启系统"
    echo "  2) 返回主菜单"
    echo "  3) 退出脚本"
    
    read -p "请输入选项 [1-3]: " -r choice
    case $choice in
        1)
            print_warn "系统将在 10 秒后重启..."
            sleep 10
            run_cmd "reboot"
            ;;
        2)
            print_info "返回主菜单..."
            ;;
        3)
            print_info "感谢使用，脚本退出！"
            exit 0
            ;;
        *)
            print_info "返回主菜单..."
            ;;
    esac
}

# ========== 卸载管理 ==========
uninstall_management() {
    print_title "卸载管理"
    reset_question_stack
    
    if check_lockfile; then
        read_lockfile
        print_info "检测到安装记录:"
        echo "----------------------------------------"
        echo "安装用户: $TARGET_USER"
        echo "桌面环境: $DESKTOP_TYPE"
        echo "VNC端口: $VNC_PORT"
        echo "VNC密码: $VNC_PASSWORD"
        echo "浏览器: $BROWSER_CHOICE"
        echo "noVNC: $INSTALL_NOVNC"
        echo "----------------------------------------"
    else
        print_warn "未找到安装记录锁文件"
    fi
    
    echo
    echo "请选择要卸载的组件:"
    echo "  1) 卸载桌面环境"
    echo "  2) 卸载 VNC Server"
    echo "  3) 卸载 noVNC"
    echo "  4) 卸载浏览器"
    echo "  5) 卸载应用程序"
    echo "  6) 完整卸载"
    echo "  0) 返回主菜单"
    echo
    
    uninstall_type=$(ask_input "请输入数字 [0-6]" "select_uninstall_type" "")
    local res=$?
    if [[ $res -eq 1 ]]; then
        BACK_TO_PREV=0
        return
    fi
    
    case $uninstall_type in
        1)
            print_warn "即将卸载桌面环境"
            confirm_action "确认继续" "confirm_uninstall_desktop"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            case "$DESKTOP_TYPE" in
                xfce4|xfce-lite|xubuntu)
                    run_cmd "apt remove -y xfce4 xfce4-goodies xfce4-terminal xubuntu-desktop"
                    ;;
                lxqt)
                    run_cmd "apt remove -y lxqt"
                    run_cmd "add-apt-repository --remove ppa:lxqt/stable -y"
                    ;;
                kde*)
                    run_cmd "apt remove -y kde-full kde-standard kde-plasma-desktop"
                    ;;
                mate*)
                    run_cmd "apt remove -y mate-desktop-environment-core mate-desktop-environment-extras"
                    ;;
                gnome*)
                    run_cmd "apt remove -y ubuntu-gnome-desktop ubuntu-desktop"
                    ;;
            esac
            run_cmd "apt autoremove -y"
            print_success "桌面环境卸载完成"
            ;;
            
        2)
            print_warn "即将卸载 TigerVNC"
            confirm_action "确认继续" "confirm_uninstall_vnc"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            run_cmd "apt remove -y tigervnc-standalone-server tigervnc-xorg-extension"
            run_cmd "rm -rf $TARGET_HOME/.vnc 2>/dev/null"
            run_cmd "rm -f /etc/systemd/system/vncserver@*.service"
            run_cmd "systemctl daemon-reload"
            run_cmd "apt autoremove -y"
            print_success "VNC 卸载完成"
            ;;
            
        3)
            print_warn "即将卸载 noVNC"
            confirm_action "确认继续" "confirm_uninstall_novnc"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            local uninstall_cmd="bash <(curl -L http://sh.802213.xyz/novnc/uninstall_auto.sh)"
            run_cmd "$uninstall_cmd" || print_warn "noVNC 卸载脚本执行失败"
            print_success "noVNC 卸载完成"
            ;;
            
        4)
            print_warn "即将卸载浏览器"
            confirm_action "确认继续" "confirm_uninstall_browser"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            echo "请选择要卸载的浏览器（可多选）:"
            echo "  1) Firefox"
            echo "  2) Microsoft Edge"
            echo "  3) Google Chrome"
            
            browser_uninstall=$(ask_input "请输入序号" "select_uninstall_browser" "")
            local res=$?
            if [[ $res -eq 1 ]]; then
                BACK_TO_PREV=0
                return
            fi
            
            for choice in $browser_uninstall; do
                case $choice in
                    1)
                        run_cmd "apt remove -y firefox"
                        ;;
                    2)
                        run_cmd "apt remove -y microsoft-edge-stable"
                        remove_browser_repo "edge"
                        ;;
                    3)
                        run_cmd "apt remove -y google-chrome-stable"
                        remove_browser_repo "google"
                        ;;
                esac
            done
            run_cmd "apt autoremove -y"
            print_success "浏览器卸载完成"
            ;;
            
        5)
            print_warn "即将卸载应用程序"
            confirm_action "确认继续" "confirm_uninstall_apps"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            echo "请选择要卸载的应用（可多选）:"
            echo "  1) Fcitx5"
            echo "  2) VS Code"
            echo "  3) VLC"
            echo "  4) MPV"
            echo "  5) LibreOffice"
            echo "  6) Flameshot"
            echo "  7) 压缩工具"
            echo "  8) 系统工具"
            echo "  9) QQ"
            echo " 10) 微信"
            echo " 11) FinalShell"
            echo " 12) Cursor"
            echo " 13) RealVNC Viewer"
            echo " 14) IBus"
            
            app_uninstall=$(ask_input "请输入序号" "select_uninstall_apps" "")
            local res=$?
            if [[ $res -eq 1 ]]; then
                BACK_TO_PREV=0
                return
            fi
            
            for choice in $app_uninstall; do
                case $choice in
                    1) run_cmd "apt remove -y fcitx5*" ;;
                    2) run_cmd "apt remove -y code" ;;
                    3) run_cmd "apt remove -y vlc" ;;
                    4) run_cmd "apt remove -y mpv" ;;
                    5) run_cmd "apt remove -y libreoffice*" ;;
                    6) run_cmd "apt remove -y flameshot" ;;
                    7) run_cmd "apt remove -y p7zip-full unrar" ;;
                    8) run_cmd "apt remove -y neofetch htop tmux" ;;
                    9) run_cmd "dpkg -r qq 2>/dev/null || true" ;;
                    10) run_cmd "dpkg -r wechat 2>/dev/null || true" ;;
                    11) run_cmd "dpkg -r finalshell 2>/dev/null || true" ;;
                    12) run_cmd "apt remove -y cursor 2>/dev/null || true" ;;
                    13) run_cmd "dpkg -r realvnc-vnc-viewer 2>/dev/null || true" ;;
                    14) run_cmd "apt remove -y ibus* 2>/dev/null || true" ;;
                esac
            done
            run_cmd "apt autoremove -y"
            print_success "应用程序卸载完成"
            ;;
            
        6)
            print_warn "完整卸载"
            confirm_action "确认执行完整卸载" "confirm_full_uninstall"
            local res=$?
            if [[ $res -eq 1 ]] || [[ $res -eq 2 ]]; then
                return
            fi
            
            run_cmd "apt remove -y xfce4 xubuntu-desktop lxqt kde-full kde-standard kde-plasma-desktop mate-desktop-environment-core mate-desktop-environment-extras ubuntu-gnome-desktop ubuntu-desktop"
            run_cmd "apt remove -y tigervnc-standalone-server tigervnc-xorg-extension"
            run_cmd "rm -rf $TARGET_HOME/.vnc 2>/dev/null"
            run_cmd "rm -f /etc/systemd/system/vncserver@*.service"
            run_cmd "systemctl daemon-reload"
            run_cmd "bash <(curl -L http://sh.802213.xyz/novnc/uninstall_auto.sh) 2>/dev/null || true"
            run_cmd "apt remove -y firefox microsoft-edge-stable google-chrome-stable"
            remove_browser_repo "edge"
            remove_browser_repo "google"
            run_cmd "apt remove -y fcitx5* code vlc mpv libreoffice* flameshot p7zip-full unrar neofetch htop tmux ibus*"
            run_cmd "dpkg -r qq wechat finalshell realvnc-vnc-viewer 2>/dev/null || true"
            run_cmd "apt remove -y cursor 2>/dev/null || true"
            run_cmd "apt autoremove -y"
            run_cmd "rm -f $LOCKFILE"
            
            print_success "完整卸载完成！"
            ;;
            
        0) return ;;
    esac
    
    read -p "按回车键返回主菜单..." -r
}

# ========== 服务管理 ==========
service_management() {
    print_title "服务管理"
    reset_question_stack
    
    if ! check_lockfile; then
        print_error "未找到安装记录，无法管理服务！"
        sleep 2
        return
    fi
    
    read_lockfile
    local display_num=$(port_to_display $VNC_PORT)
    local service_name="vncserver@$display_num.service"
    
    echo "当前 VNC 服务状态:"
    run_cmd "systemctl status $service_name --no-pager" 2>/dev/null || print_warn "服务未运行"
    echo
    
    echo "请选择操作:"
    echo "  1) 启动 VNC 服务"
    echo "  2) 停止 VNC 服务"
    echo "  3) 重启 VNC 服务"
    echo "  4) 设置开机自启"
    echo "  5) 取消开机自启"
    echo "  6) 修改 VNC 密码"
    echo "  7) 查看连接信息"
    echo "  0) 返回主菜单"
    echo
    
    service_action=$(ask_input "请输入数字 [0-7]" "select_service_action" "")
    local res=$?
    if [[ $res -eq 1 ]]; then
        BACK_TO_PREV=0
        return
    fi
    
    case $service_action in
        1)
            run_cmd "systemctl start $service_name"
            print_success "VNC 服务启动成功"
            ;;
        2)
            run_cmd "systemctl stop $service_name"
            print_success "VNC 服务停止成功"
            ;;
        3)
            run_cmd "systemctl restart $service_name"
            print_success "VNC 服务重启成功"
            ;;
        4)
            run_cmd "systemctl enable $service_name"
            print_success "已设置开机自启"
            ;;
        5)
            run_cmd "systemctl disable $service_name"
            print_success "已取消开机自启"
            ;;
        6)
            print_info "修改 VNC 密码"
            while true; do
                read -s -p "请输入新的 VNC 密码: " new_vnc_pass
                echo
                read -s -p "请再次输入: " new_vnc_pass_confirm
                echo
                if [[ "$new_vnc_pass" != "$new_vnc_pass_confirm" ]]; then
                    print_error "两次密码不一致"
                    continue
                fi
                if [[ -z "$new_vnc_pass" ]]; then
                    print_error "密码不能为空"
                    continue
                fi
                if [[ "$TARGET_USER" == "root" ]]; then
                    printf "%s\n%s\nn\n" "$new_vnc_pass" "$new_vnc_pass" | vncpasswd >/dev/null 2>&1
                else
                    runuser -l "$TARGET_USER" -c "printf '%s\n%s\nn\n' \"$new_vnc_pass\" \"$new_vnc_pass\" | vncpasswd >/dev/null 2>&1"
                fi
                VNC_PASSWORD="$new_vnc_pass"
                generate_lockfile
                print_success "VNC 密码修改成功"
                break
            done
            ;;
        7)
            local public_ip=$(get_public_ip)
            print_title "连接信息"
            echo "安装用户: $TARGET_USER"
            echo "公网 IP: $public_ip"
            echo "VNC 端口: $VNC_PORT"
            echo "VNC 密码: $VNC_PASSWORD"
            if [[ "$INSTALL_NOVNC" == "y" ]]; then
                echo "noVNC 地址: http://$public_ip:${NOVNC_PORT:-6080}/vnc.html"
            fi
            echo
            echo "VNC 连接命令: vncviewer $public_ip:$VNC_PORT"
            ;;
        0) return ;;
    esac
    
    read -p "按回车键返回主菜单..." -r
}

# ========== 主菜单（根据锁文件状态动态显示） ==========
main_menu() {
    # 每次进入主菜单前检测锁文件状态（更新 INSTALLED 标志）
    if [[ -n "$LOCKFILE" && -f "$LOCKFILE" ]]; then
        INSTALLED=true
    else
        INSTALLED=false
    fi

    while true; do
        clear_screen
        echo -e "\n${WHITE}======= 主菜单 =======${NC}"
        
        if [[ "$INSTALLED" == false ]]; then
            echo "  1) 自动安装"
            echo "  2) 高级安装"
        else
            echo -e "${YELLOW}  已检测到安装记录，安装选项已隐藏${NC}"
        fi
        
        echo "  3) 独立应用安装"
        echo "  4) 应用批量管理"
        echo "  5) 卸载管理"
        echo "  6) 服务管理"
        echo "  7) 查看系统信息"
        echo "  0) 退出脚本"
        echo -e "${WHITE}=====================${NC}"
        
        read -p "请输入选项 [0-7]: " main_choice
        case $main_choice in
            1)
                if [[ "$INSTALLED" == false ]]; then
                    auto_install
                else
                    print_error "无效选项"
                fi
                ;;
            2)
                if [[ "$INSTALLED" == false ]]; then
                    advanced_install
                else
                    print_error "无效选项"
                fi
                ;;
            3) install_apps_menu ;;
            4) app_batch_menu ;;
            5) uninstall_management ;;
            6) service_management ;;
            7)
                print_title "系统信息"
                run_cmd "neofetch 2>/dev/null || cat /etc/os-release | head -n 2"
                echo "公网 IP: $(get_public_ip)"
                echo "当前目标用户: $TARGET_USER"
                if check_lockfile; then
                    echo "检测到安装记录: $LOCKFILE"
                else
                    echo "未检测到安装记录"
                fi
                read -p "按回车键返回主菜单..." -r
                ;;
            0)
                print_info "感谢使用，脚本退出！"
                exit 0
                ;;
            *) print_error "无效选择，请重试"; sleep 1 ;;
        esac
    done
}

# ========== 脚本入口 ==========
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! is_root && ! has_sudo; then
        print_error "当前用户无 sudo 权限"
        exit 1
    fi
    # 启动时自动检测锁文件
    detect_existing_lockfile
    main_menu
fi
