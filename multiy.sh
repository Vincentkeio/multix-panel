#!/bin/bash
# Hub-Next Panel Ver 1.0

export M_ROOT="/opt/hubnp_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/hubnp ] && cp "$0" /usr/bin/hubnp && chmod +x /usr/bin/hubnp; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }
_deploy_service() {
    local name=$1
    local cmd=$2
    local workdir=$(dirname "$cmd")
    cat > "/etc/systemd/system/${name}.service" <<EOF
[Unit]
Description=${name} Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=${workdir}
ExecStart=/usr/bin/python3 ${cmd}
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${name}"
    systemctl restart "${name}"
}
# --- [ 深度清理中心：Hub-Next 旗舰全向兼容版 ] ---
env_cleaner() {
    echo -e "${YELLOW}>>> 正在执行环境物理级大扫除 (锁定服务名: hub-next-panel)...${PLAIN}"
    
    # 1. 停止并禁用所有相关服务 (含旧版 multix/multiy 兼容抹除)
    # 增加通配符，确保 hub-next-panel 和 hub-next-api 同时被捕获
    echo -e "${YELLOW}正在物理停止所有旧版与当前服务...${PLAIN}"
    systemctl stop hub-next-* multiy-* multix* 2>/dev/null
    systemctl disable hub-next-* multiy-* multix* 2>/dev/null
    
    # 2. 移除所有版本的系统服务文件并刷新守护进程
    rm -f /etc/systemd/system/hub-next-* /etc/systemd/system/multiy-* /etc/systemd/system/multix-* 2>/dev/null
    systemctl daemon-reload
    
    # 3. 强制杀死残留进程 (精准匹配路径关键字与旧版特征)
    echo -e "${YELLOW}正在清理物理进程池残留...${PLAIN}"
    pkill -9 -f "master/app.py" 2>/dev/null
    pkill -9 -f "agent/agent.py" 2>/dev/null
    pkill -9 -f "hub-next" 2>/dev/null
    pkill -9 -f "multix" 2>/dev/null
    pkill -9 -f "multiy" 2>/dev/null
    
    # 4. 定点强杀端口占用 (基于 lsof 实时探测)
    # 自动获取 .env 中的自定义端口，若无则使用默认值
    local P_WEB=${M_PORT:-7575}
    local P_API=${M_WS_PORT:-9339}
    
    for port in "$P_WEB" "$P_API" 5959 5858; do
        local pid=$(lsof -t -i:"$port" 2>/dev/null)
        if [ ! -z "$pid" ]; then
            echo -e "${YELLOW}发现端口 $port 被进程 $pid 占用，强制释放...${PLAIN}"
            kill -9 "$pid" 2>/dev/null
        fi
    done

    # 5. 【核心重构】物理重置 UI 缓存与路径自愈
    echo -e "${YELLOW}正在执行 UI 物理路径重置与自愈...${PLAIN}"
    # 彻底抹除 templates 和 static，防止旧版 HTML 碎片干扰新版 UI
    rm -rf "$M_ROOT/master/templates"
    rm -rf "$M_ROOT/master/static"
    
    # 重新构建符合 Hub-Next 标准的目录结构
    mkdir -p "$M_ROOT/master/templates/modals"
    mkdir -p "$M_ROOT/master/static"

    # 6. 环境依赖校准
    echo -e "${YELLOW}正在校准 Python 环境依赖...${PLAIN}"
    if ! command -v lsof &> /dev/null; then
        apt-get update && apt-get install -y lsof >/dev/null 2>&1
    fi
    
    # 物理清除可能导致异步冲突的旧版 SocketIO 库，强制使用 Hub-Next 推荐的轻量三件套
    python3 -m pip uninstall -y python-socketio eventlet python-engineio 2>/dev/null
    python3 -m pip install --upgrade flask websockets psutil --break-system-packages 2>/dev/null
    
    echo -e "${GREEN}>>> 物理大扫除完成。Hub-Next 环境已完全纯净，可开始安装。${PLAIN}"
}

# --- [ Hub-Next Panel 凭据管理中心：看板 + 修改一体化 ] ---
credential_center() {
    while true; do
        clear
        [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}[错误]${PLAIN} 尚未安装主控！" && pause_back && return
        source "$M_ROOT/.env"
        
        # 实时环境获取
        V4=$(curl -s4m 2 api.ipify.org || echo "N/A")
        V6=$(curl -s6m 2 api64.ipify.org || echo "未分配")
        WS_PORT=${M_WS_PORT:-9339}

        echo -e "${SKYBLUE}==================================================${PLAIN}"
        echo -e "         🛰️  Hub-Next Panel 凭据管理中心"
        echo -e "             Ver 1.0 (Build 202512)"
        echo -e "${SKYBLUE}==================================================${PLAIN}"
        
        echo -e "${GREEN}[ 1. 当前运行凭据 ]${PLAIN}"
        # 针对双栈访问入口进行分权显示
        echo -e " 🔹 IPv4 入口: ${YELLOW}http://$V4:$M_PORT${PLAIN}"
        
        # 判断 V6 是否有效，若有效则按标准格式封装显示
        if [[ "$V6" != "未分配" && "$V6" != "N/A" ]]; then
            echo -e " 🔹 IPv6 入口: ${YELLOW}http://[$V6]:$M_PORT${PLAIN}"
        else
            echo -e " 🔹 IPv6 入口: ${RED}未检测到有效公网 IPv6 地址${PLAIN}"
        fi
        
        echo -e " 🔹 管理账号: ${SKYBLUE}$M_USER${PLAIN}"
        echo -e " 🔹 管理密码: ${SKYBLUE}$M_PASS${PLAIN}"
        echo -e " 🔹 通信令牌: ${SKYBLUE}$M_TOKEN${PLAIN}"
        echo -e " 🔹 WEB 面板端口: ${SKYBLUE}$M_PORT${PLAIN}"
        echo -e " 🔹 API 监听端口: ${SKYBLUE}$WS_PORT${PLAIN}"
        
        echo -e "\n${GREEN}[ 2. 物理监听状态 ]${PLAIN}"
        echo -ne " 🔹 面板服务 ($M_PORT): " && _check_port_stat "$M_PORT"
        echo -ne " 🔹 API 服务 ($WS_PORT): " && _check_port_stat "$WS_PORT"
        
        echo -e "\n${YELLOW}--------------------------------------------------${PLAIN}"
        echo -e " 1) 修改 管理用户名       2) 修改 管理密码"
        echo -e " 3) 修改 通信令牌(Token)  4) 修改 面板 Web 端口"
        echo -e " 5) 修改 API 监听端口     6) ${RED}一键重置所有凭据${PLAIN}"
        echo -e " 0) 返回主菜单"
        echo -e "${YELLOW}--------------------------------------------------${PLAIN}"
        read -p "请选择操作 [0-6]: " opt

        case $opt in
            1) _update_env "M_USER" "管理用户名" ;;
            2) _update_env "M_PASS" "管理密码" ;;
            3) _update_env "M_TOKEN" "通信令牌" ;;
            4) _update_env "M_PORT" "面板 Web 端口" ;;
            5) _update_env "M_WS_PORT" "API 监听端口" ;;
            6) _reset_all_credentials ;;
            0) break ;;
            *) echo -e "${RED}无效选择${PLAIN}" && sleep 1 ;;
        esac
    done
}

# --- [ 核心：物理更新逻辑 ] ---
_update_env() {
    local key=$1
    local name=$2
    read -p "请输入新的${name}: " new_val
    [ -z "$new_val" ] && echo -e "${RED}输入不能为空！${PLAIN}" && sleep 1 && return

    echo -e "${YELLOW}>>> 正在同步物理配置...${PLAIN}"
    # 使用 sed 精准替换 .env 文件中的键值对
    sed -i "s/^${key}=.*/${key}=${new_val}/" "$M_ROOT/.env"
    
    # 立即重载服务以生效
    _apply_and_restart
}

# --- [ 核心：应用配置并物理重启 ] ---
_apply_and_restart() {
    source "$M_ROOT/.env"
    echo -e "${YELLOW}>>> 正在重启 Hub-Next 系统组件...${PLAIN}"
    
    # 重启面板和API服务
systemctl restart hub-next-panel
    
    echo -e "${GREEN}>>> 配置已生效！${PLAIN}"
    sleep 2
}

# --- [ 辅助：端口状态探测 ] ---
_check_port_stat() {
    local port=$1
    local has_v4=$(ss -lnpt4 | grep -q ":$port " && echo "yes" || echo "no")
    local has_v6=$(ss -lnpt6 | grep -q ":$port " && echo "yes" || echo "no")
    
    if [ "$has_v4" == "yes" ]; then echo -ne "${GREEN}● IPv4 OK ${PLAIN}"; else echo -ne "${RED}○ IPv4 OFF ${PLAIN}"; fi
    if [ "$has_v6" == "yes" ]; then echo -ne "${GREEN}● IPv6 OK${PLAIN}"; else echo -ne "${RED}○ IPv6 OFF${PLAIN}"; fi
    echo ""
}

# --- [ 辅助：一键重置凭据 ] ---
_reset_all_credentials() {
    read -p "确认重置所有凭据为初始状态？[y/n]: " res
    [ "$res" != "y" ] && return
    
    local new_pass=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
    local new_token=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    
    sed -i "s/^M_USER=.*/M_USER=admin/" "$M_ROOT/.env"
    sed -i "s/^M_PASS=.*/M_PASS=${new_pass}/" "$M_ROOT/.env"
    sed -i "s/^M_TOKEN=.*/M_TOKEN=${new_token}/" "$M_ROOT/.env"
    
    _apply_and_restart
    echo -e "${GREEN}凭据已重置！新密码: $new_pass${PLAIN}"
    pause_back
}
# --- [ 2. 主控安装：旗舰加固版 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Hub-Next Panel Ver 1.0 主控${PLAIN}"
    apt-get install -y python3-pip
    
    # 1. 物理环境预优化：强制开启内核双栈监听映射 (修复 IPv4 OFF 问题)
    echo -e "${YELLOW}>>> 优化系统内核双栈通信参数...${PLAIN}"
    sysctl -w net.ipv6.bindv6only=0 >/dev/null 2>&1

    # 2. 物理目录强制初始化
    mkdir -p "$M_ROOT/master/static"
    mkdir -p "$M_ROOT/master/templates/modals"

echo -e "\n${YELLOW}--- 交互式设置 (回车使用默认值) ---${PLAIN}"
    

    # 1. 管理员账号与密码
    read -p "1. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "2. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    # 2. 面板 Web 端口交互 (仅保留这一个)
    read -p "3. 面板 Web 端口 [默认 7575]: " M_PORT
    if [[ ! "$M_PORT" =~ ^[0-9]+$ ]] || [ "$M_PORT" -lt 1 ] || [ "$M_PORT" -gt 65535 ]; then
        M_PORT=7575
        echo -e "${YELLOW}[提示] 输入端口无效，已回退至默认: 7575${PLAIN}"
    fi

    # 4. 接入监听端口交互 (WebSocket) - 替换掉原来重复的 Web 端口项
    while true; do
        read -p "4. 接入监听端口 (WS) [默认 9339]: " M_WS_PORT
        M_WS_PORT=${M_WS_PORT:-9339}
        
        if [[ ! "$M_WS_PORT" =~ ^[0-9]+$ ]] || [ "$M_WS_PORT" -lt 1 ] || [ "$M_WS_PORT" -gt 65535 ]; then
            echo -e "${RED}[错误] 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
            continue
        fi

        if [ "$M_WS_PORT" == "$M_PORT" ]; then
            echo -e "${RED}[错误] 接入端口不能与面板 Web 端口 ($M_PORT) 相同，请重新输入。${PLAIN}"
            continue
        fi
        
        echo -e "${GREEN}[确认] 接入端口已设为: $M_WS_PORT${PLAIN}"
        break
    done

    # --- [ 后接您之前的域名检测逻辑 ] ---
    # 5. 主控公网域名配置：含组件自愈与双栈解析探测
    if ! command -v host &> /dev/null; then
        echo -e "${YELLOW}[提示] 缺失域名探测组件，正在尝试自动安装修复...${PLAIN}"
        if [[ -f /etc/redhat-release ]]; then
            yum install -y bind-utils &> /dev/null
        else
            apt-get update &> /dev/null && apt-get install -y dnsutils &> /dev/null
        fi
        if ! command -v host &> /dev/null; then
            echo -e "${RED}[错误] 自动修复失败！请手动执行 'apt install dnsutils' 后重新运行。${PLAIN}"
            exit 1
        fi
    fi

    while true; do
        echo -e "\n${BLUE}5: 配置主控访问域名${PLAIN}"
        read -p "请输入主控公网域名 (严禁填IP): " M_HOST
        if [[ ! "$M_HOST" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
            echo -e "${RED}[错误] 格式无效！必须填写已解析的域名。${PLAIN}"
            continue
        fi

        echo -e "${YELLOW}[检测] 正在验证域名解析状态，请稍候...${PLAIN}"
        LOCAL_IP4=$(curl -s4 --connect-timeout 5 api.ipify.org || curl -s4 --connect-timeout 5 icanhazip.com || echo "none")
        LOCAL_IP6=$(curl -s6 --connect-timeout 5 api64.ipify.org || curl -s6 --connect-timeout 5 6.icanhazip.com || echo "none")
        LOCAL_IP4=$(echo $LOCAL_IP4 | tr -d '[:space:]')
        LOCAL_IP6=$(echo $LOCAL_IP6 | tr -d '[:space:]')

        DNS_IP4=$(host -t A "$M_HOST" 8.8.8.8 | grep "has address" | awk '{print $NF}' | head -n1)
        DNS_IP6=$(host -t AAAA "$M_HOST" 8.8.8.8 | grep "has IPv6 address" | awk '{print $NF}' | head -n1)

        IS_V4_MATCH=false
        IS_V6_MATCH=false

        if [[ -n "$DNS_IP4" && "$DNS_IP4" == "$LOCAL_IP4" ]]; then
            echo -e "${GREEN}[✔] IPv4 解析匹配成功: $DNS_IP4${PLAIN}"; IS_V4_MATCH=true
        fi
        if [[ -n "$DNS_IP6" && "$DNS_IP6" == "$LOCAL_IP6" ]]; then
            echo -e "${GREEN}[✔] IPv6 解析匹配成功: $DNS_IP6${PLAIN}"; IS_V6_MATCH=true
        fi

        if $IS_V4_MATCH || $IS_V6_MATCH; then
            echo -e "${GREEN}[成功] 域名解析检测通过！${PLAIN}"; break
        else
            echo -e "${RED}[拒绝] 域名解析检测失败！${PLAIN}"
            echo -e "${YELLOW}请将 $M_HOST 解析至 A->$LOCAL_IP4 或 AAAA->$LOCAL_IP6${PLAIN}"
        fi
    done

    # 6. Token 生成
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "6. 通信令牌 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}

    # --- [ 写入配置与防火墙自动放行 ] ---
    echo -e "${YELLOW}>>> 正在同步物理配置并配置防火墙...${PLAIN}"
    
    # 物理放行自定义端口
    ufw allow "$M_PORT"/tcp >/dev/null 2>&1; iptables -I INPUT -p tcp --dport "$M_PORT" -j ACCEPT >/dev/null 2>&1
    ufw allow "$M_WS_PORT"/tcp >/dev/null 2>&1; iptables -I INPUT -p tcp --dport "$M_WS_PORT" -j ACCEPT >/dev/null 2>&1

    # 持久化环境变量
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_WS_PORT='$M_WS_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF

    # 2. 生成后端核心 (app.py)
    # 请确保脚本下方的 _generate_master_py 函数已更新为包含 /sub 和 /api/gen_keys 的版本
    _generate_master_py

    # 3. 从 GitHub 同步 UI 资源
    local RAW_URL="https://raw.githubusercontent.com/Vincentkeio/multix-panel/main/ui"
    local V_CACHE="?v=$(date +%s)"
    echo -e "${YELLOW}>>> 正在同步云端 UI 资源 (全量自动化清单)...${PLAIN}"
    
_download_ui() {
    local file=$1
    local target="$M_ROOT/master/$file"
    
    # 物理修复：在写入文件前，强制创建其所在的父目录路径
    mkdir -p "$(dirname "$target")"
    
    echo -ne "  🔹 正在同步 ${file} ... "
    # 使用 -L 跟踪重定向，并增加随机数绕过 GitHub CDN 缓存
    curl -sL -o "$target" "${RAW_URL}/${file}?v=$(date +%s)"
    
    # 严格校验：文件必须存在且不为空，且不包含 404 错误文本
    if [ ! -s "$target" ] || grep -q "404: Not Found" "$target"; then
        echo -e "${RED}[失败]${PLAIN}"
        return 1
    else
        echo -e "${GREEN}[OK]${PLAIN}"
    fi
}

# 4. 【核心配置】：UI 文件全量清单 (已剔除 drawer.html，新增组件化模块)
    UI_FILES=(
        "templates/index.html"
        "templates/master_status.html"
        "templates/action_bar.html"
        "templates/main_nodes.html"
        "templates/modals_container.html"
        "templates/modals/admin_modal.html"
        "templates/modals/login_modal.html"
        "static/tailwind.js"
        "static/alpine.js"
        "static/dashboard.js"
        "static/custom.css"
        "static/qrcode.min.js"
    )

    # 5. 执行物理清理后再同步 (确保无旧版脏数据)
    echo -e "${YELLOW}>>> 正在同步云端 UI 资源 (全量自动化清单)...${PLAIN}"
    rm -rf "$M_ROOT/master/templates" "$M_ROOT/master/static"
    
    for file in "${UI_FILES[@]}"; do
        # 内部调用已修复路径自愈能力的 _download_ui
        _download_ui "$file"
    done

    # 6. 部署并启动系统服务
    _deploy_service "hub-next-panel" "$M_ROOT/master/app.py"
    
    echo -e "${GREEN}✅ 旗舰版主控部署完成。${PLAIN}"; sleep 2; credential_center
}
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess, psutil, platform, random, threading, socket, base64
from flask import Flask, request, jsonify, send_from_directory, render_template

# 1. 基础配置
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
M_ROOT = "/opt/hubnp_mvp"
ENV_PATH = f"{M_ROOT}/.env"
DB_PATH = f"{M_ROOT}/agents_db.json"

app = Flask(__name__, 
            template_folder=os.path.join(BASE_DIR, 'templates'),
            static_folder=os.path.join(BASE_DIR, 'static'))

# --- [ 数据库管理 ] ---
def load_db():
    if not os.path.exists(DB_PATH): return {}
    try:
        with open(DB_PATH, 'r', encoding='utf-8') as f:
            db = json.load(f)
        nodes = list(db.items())
        # 排序逻辑：Order 为 0 的排最后，其他按数字升序
        nodes.sort(key=lambda x: (x[1].get('order') == 0, x[1].get('order', 999)))
        cleaned_db = {}
        for i, (uid, data) in enumerate(nodes, 1):
            data['order'] = i
            cleaned_db[uid] = data
        return cleaned_db
    except: return {}

def save_db(db_data):
    with open(DB_PATH, 'w', encoding='utf-8') as f:
        json.dump(db_data, f, indent=4, ensure_ascii=False)

def load_env():
    c = {}
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l:
                    k, v = l.strip().split('=', 1)
                    c[k] = v.strip("'\"")
    return c

# 初始化全局变量
env = load_env()
ADMIN_USER = env.get('M_USER', 'admin')
ADMIN_PASS = env.get('M_PASS', 'admin')
TOKEN = env.get('M_TOKEN', 'admin')
AGENTS_LIVE = {}
WS_CLIENTS = {}

# --- [ 1. 认证路由 ] ---
@app.route('/api/login', methods=['POST'])
def login():
    try:
        data = request.get_json()
        if data.get('user') == ADMIN_USER and data.get('pass') == ADMIN_PASS:
            return jsonify({"status": "success", "token": TOKEN})
        return jsonify({"status": "fail", "msg": "Invalid Credentials"}), 401
    except:
        return jsonify({"status": "error"}), 500

# --- [ 2. 状态路由 ] ---
@app.route('/api/state')
def get_state():
    db = load_db()
    master_info = {
        "cpu": psutil.cpu_percent(),
        "mem": psutil.virtual_memory().percent,
        "disk": psutil.disk_usage('/').percent,
        "sys_ver": f"{platform.system()} {platform.release()}",
        "sb_ver": subprocess.getoutput("sing-box version").split(' ')[2] if os.path.exists("/usr/bin/sing-box") else "N/A"
    }
    processed_agents = {}
    for sid, agent in db.items():
        processed_agents[sid] = agent
        processed_agents[sid]['status'] = 'online' if sid in AGENTS_LIVE else 'offline'
        if sid in AGENTS_LIVE:
            processed_agents[sid]['metrics'] = AGENTS_LIVE[sid].get('metrics', {})
            
    return jsonify({
        "master": master_info,
        "agents": processed_agents,
        "config": {
            "user": ADMIN_USER, 
            "token": TOKEN, 
            "ip4": env.get('M_HOST', '0.0.0.0'),
            "port": env.get('M_PORT', '7575'),
            "ws_port": env.get('M_WS_PORT', '9339')
        }
    })

# --- [ 3. 核心修复：修复缩进与防火墙逻辑 ] ---
@app.route('/api/update_admin', methods=['POST'])
def update_admin():
    try:
        d = request.get_json()
        if request.headers.get('Authorization') != TOKEN:
            return jsonify({"status": "fail", "msg": "Unauthorized"}), 403

        new_user = d.get('user')
        new_pass = d.get('pass')
        new_token = d.get('token')
        new_host = d.get('host')
        new_port = str(d.get('port'))
        new_ws_port = str(d.get('ws_port'))

        # 1. 持久化写入
        with open(ENV_PATH, 'w', encoding='utf-8') as f:
            f.write(f"M_USER='{new_user}'\n")
            f.write(f"M_PASS='{new_pass}'\n")
            f.write(f"M_TOKEN='{new_token}'\n")
            f.write(f"M_PORT='{new_port}'\n")
            f.write(f"M_WS_PORT='{new_ws_port}'\n")
            f.write(f"M_HOST='{new_host}'\n")

        # 2. 异步执行：防火墙自愈 + 服务重启 (物理对齐修复点)
        def maintenance_task():
            import time
            time.sleep(1)
            # 严格 12 空格缩进对齐
            for p in [new_port, new_ws_port]:
                os.system(f"ufw allow {p}/tcp > /dev/null 2>&1")
                os.system(f"iptables -I INPUT -p tcp --dport {p} -j ACCEPT > /dev/null 2>&1")
            # 修正后的位置，确保前缀 12 个空格
            os.system("systemctl restart hub-next-panel")

        threading.Thread(target=maintenance_task).start()
        return jsonify({"status": "success", "msg": "Config updated."})
    
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500
        
# --- [ 其余路由逻辑 ] ---
@app.route('/api/manage_agent', methods=['POST'])
def manage_agent():
    d = request.json
    if request.headers.get('Authorization') != TOKEN: return jsonify({"res":"fail"}), 403
    db = load_db()
    sid, action, val = d.get('sid'), d.get('action'), d.get('value')
    if action == 'alias': db[sid]['alias'] = val
    elif action == 'hide': db[sid]['hidden'] = not db[sid].get('hidden', False)
    elif action == 'reorder': db[sid]['order'] = int(val)
    elif action == 'delete': 
        if sid in db: del db[sid]
    elif action == 'add_virtual':
        v_id = f"virtual-{random.randint(1000,9999)}"
        db[v_id] = {"hostname": "VIRTUAL-NODE", "alias": "演示节点", "is_demo": True, "order": 99}
    save_db(db)
    return jsonify({"res": "ok"})

@app.route('/')
def serve_index(): return render_template('index.html')

@app.route('/static/<path:filename>')
def serve_static(filename): return send_from_directory(os.path.join(BASE_DIR, 'static'), filename)

@app.route('/sub')
def sub_handler():
    db, curr_env = load_db(), load_env()
    token, sub_type = request.args.get('token'), request.args.get('type', 'v2ray')
    if token != TOKEN: return "Unauthorized", 403
    links = []
    for sid, agent in db.items():
        if agent.get('hidden'): continue
        ip = agent.get('ip') or curr_env.get('M_HOST')
        for inb in agent.get('metrics', {}).get('inbounds', []):
            if inb.get('type') == 'vless':
                tag, uuid = inb.get('tag', 'Node'), inb.get('uuid')
                port = inb.get('listen_port') or inb.get('port')
                links.append(f"vless://{uuid}@{ip}:{port}?security=reality&sni=yahoo.com&type=tcp&flow=xtls-rprx-vision#{tag}")
    res = '\n'.join(links)
    return base64.b64encode(res.encode()).decode() if sub_type != 'clash' else res

@app.route('/api/gen_keys')
def gen_keys():
    try:
        out = subprocess.getoutput("sing-box generate reality-keypair").split('\n')
        return jsonify({"private_key": out[0].split(': ')[1].strip(), "public_key": out[1].split(': ')[1].strip()})
    except: return jsonify({"private_key": "", "public_key": ""})

async def ws_handler(ws):
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    node_uuid = None
    try:
        async for m in ws:
            d = json.loads(m)
            # 1. 凭据校验（第一道防线）
            if d.get('token') != TOKEN: continue
            
            node_uuid = d.get('node_id')
            # 2. 从主控磁盘读取当前数据库状态
            db = load_db()
            
            # --- [ 后端 Core 判定逻辑 ] ---
            # 统计当前库中“未隐藏”的小鸡数量
            visible_count = sum(1 for node in db.values() if not node.get('hidden', False))
            
            # 判定条件：
            # 只有当此 node_uuid 是新的，且 (数据库为空 OR 数据库中小鸡全部被隐藏) 时，才执行写入
            if node_uuid not in db:
                if len(db) == 0 or visible_count == 0:
                    db[node_uuid] = {
                        "hostname": d.get('hostname', 'Node'), 
                        "order": len(db) + 1, 
                        "ip": ws.remote_address[0], 
                        "hidden": False, 
                        "alias": ""
                    }
                    # 3. 后端执行物理写入
                    save_db(db)
                    print(f"[Core] 判定通过：库为空或已全部隐藏，物理记录新节点 {node_uuid}")
            
            # 无论是否写入数据库，只要连接正常，就更新内存中的实时指标用于 UI 展示
            AGENTS_LIVE[node_uuid] = {"metrics": d.get('metrics'), "session": sid}
            
    except Exception as e:
        print(f"[WS Error] {e}")
    finally:
        WS_CLIENTS.pop(sid, None)
async def main():
    curr_env = load_env()
    web_p, ws_p = int(curr_env.get('M_PORT', 7575)), int(curr_env.get('M_WS_PORT', 9339))
    try: await websockets.serve(ws_handler, "::", ws_p, reuse_address=True)
    except: await websockets.serve(ws_handler, "0.0.0.0", ws_p, reuse_address=True)
    def run_web():
        from werkzeug.serving import make_server
        try:
            srv = make_server('::', web_p, app, threaded=True)
            srv.serve_forever()
        except:
            app.run(host='0.0.0.0', port=web_p, threaded=True, debug=False)
    threading.Thread(target=run_web, daemon=True).start()
    while True: await asyncio.sleep(3600)

if __name__ == "__main__":
    if not os.path.exists(DB_PATH): save_db({})
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
EOF
}
# --- [ 3. 被控端安装 ] ---

install_agent() {
    apt-get install -y python3-pip
    clear; echo -e "${SKYBLUE}>>> 部署 Hub-Next Panel Ver 1.0 被控 (Hybrid 状态对齐版)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或IP: " M_INPUT
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    # 安装依赖
    echo -e "${YELLOW}正在同步环境依赖...${PLAIN}"
    python3 -m pip install websockets psutil --break-system-packages --user >/dev/null 2>&1

# 自愈映射逻辑 (保留你的 IPv6 劫持方案)
    # 动态获取通信端口，如果主控端未来修改了 9339，此处可同步适配
    WS_PORT=${M_WS_PORT:-9339}

    if [[ "$M_INPUT" == *:* ]]; then
        echo -e "${YELLOW}[物理自愈] 正在为 IPv6 执行 hosts 劫持映射...${PLAIN}"
        # 移除旧的映射防止冲突
        sed -i "/multiy.local.master/d" /etc/hosts
        echo "$M_INPUT multiy.local.master" >> /etc/hosts
        FINAL_URL="ws://multiy.local.master:$WS_PORT"
    else
        FINAL_URL="ws://$M_INPUT:$WS_PORT"
    fi
    
    echo -e "${GREEN}>>> 接入地址已锁定: $FINAL_URL${PLAIN}"
    # 注入“全能仆人”逻辑
cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, websockets, json, os, subprocess, psutil, platform, time, hashlib, socket

# --- [ 仆人配置 ] ---
MASTER = "REPLACE_URL"
TOKEN = "REPLACE_TOKEN"
SB_PATH = "/usr/local/bin/sing-box"
SB_CONF = "/etc/sing-box/config.json"

class ServantCore:
    def __init__(self):
        self.last_config_hash = ""
        self.hostname = socket.gethostname()
        # --- [ 核心重构：提取硬件唯一 UUID ] ---
        self.node_id = self._get_unique_id()

    def _get_unique_id(self):
        """尝试多种方式提取物理唯一 ID，确保重装不重名"""
        try:
            # 1. 优先读取 Linux 系统机器 ID
            if os.path.exists("/etc/machine-id"):
                with open("/etc/machine-id", 'r') as f:
                    return f.read().strip()
            # 2. 备选：使用网卡硬件 MAC 地址生成的 UUID
            return str(uuid.getnode())
        except:
            # 3. 兜底：随机生成一个并记录（不推荐，通常前两步能成功）
            return "unknown-" + socket.gethostname()

    def get_config_state(self):
        """Hybrid 模式核心：读取物理配置并生成 MD5"""
        if not os.path.exists(SB_CONF):
            return {"hash": "none", "inbounds": []}
        try:
            with open(SB_CONF, 'r', encoding='utf-8') as f:
                content = f.read()
                data = json.loads(content)
                m = hashlib.md5()
                m.update(content.encode('utf-8'))
                return {"hash": m.hexdigest(), "inbounds": data.get('inbounds', [])}
        except:
            return {"hash": "error", "inbounds": []}
    def get_metrics(self):
        """采集硬盘、流量、版本等核心指标"""
        try:
            n1 = psutil.net_io_counters()
            time.sleep(0.5)
            n2 = psutil.net_io_counters()
            return {
                "cpu": int(psutil.cpu_percent()),
                "mem": int(psutil.virtual_memory().percent),
                "disk": int(psutil.disk_usage('/').percent),
                "net_up": round((n2.bytes_sent - n1.bytes_sent) / 1024 / 1024, 2),
                "net_down": round((n2.bytes_recv - n1.bytes_recv) / 1024 / 1024, 2),
                "total_up": round(n2.bytes_sent / (1024**3), 2),
                "total_down": round(n2.bytes_recv / (1024**3), 2),
                "sys_ver": f"{platform.system()} {platform.release()}",
                "sb_ver": subprocess.getoutput(f"{SB_PATH} version | head -n 1 | awk '{{print $3}}'") or "N/A"
            }
        except:
            return {"cpu":0,"mem":0,"disk":0,"net_up":0,"net_down":0,"total_up":0,"total_down":0,"sys_ver":"Err","sb_ver":"Err"}

async def main_loop(self):
        """被控端核心循环：上报状态 + 监听双向指令"""
        while True:
            try:
                # 建立 WebSocket 连接，增加超时保护
                async with websockets.connect(MASTER, ping_interval=20, ping_timeout=20) as ws:
                    print(f"[{time.ctime()}] 已连接至主控: {MASTER}")
                    
                    while True:
                        # 1. 采集当前配置状态与硬件指标
                        state = self.get_config_state()
                        payload = {
                            "type": "heartbeat",
                            "token": TOKEN,
                            "node_id": self.node_id,
                            "hostname": self.hostname,
                            "metrics": self.get_metrics(),
                            "config_hash": state['hash']
                        }
                        
                        # 2. 如果配置发生变化，主动上报完整 inbounds 列表
                        if state['hash'] != self.last_config_hash:
                            payload['type'] = "report_full"
                            payload['inbounds'] = state['inbounds']
                            self.last_config_hash = state['hash']
                        
                        # 3. 发送数据包
                        await ws.send(json.dumps(payload))

                        # 4. 进入指令监听状态，限时 5 秒防止阻塞心跳
                        try:
                            msg = await asyncio.wait_for(ws.recv(), timeout=5)
                            task = json.loads(msg)
                            
                            # A. 执行远程命令
                            if task.get('type') == 'exec_cmd' or task.get('action') == 'exec_cmd':
                                res = subprocess.getoutput(task.get('cmd'))
                                await ws.send(json.dumps({"type": "cmd_res", "data": res}))
                            
                            # B. 精准同步 Inbounds 节点配置
                            elif task.get('type') == 'update_config' or task.get('action') == 'update_config':
                                new_inbounds = task.get('inbounds', [])
                                
                                if os.path.exists(SB_CONF):
                                    # 读取本地完整配置
                                    with open(SB_CONF, 'r', encoding='utf-8') as f:
                                        full_config = json.load(f)
                                    
                                    # 仅替换 inbounds 部分，保留路由和出口设置
                                    full_config['inbounds'] = new_inbounds
                                    
                                    # 写入临时文件校验
                                    with open(SB_CONF + ".tmp", 'w', encoding='utf-8') as f:
                                        json.dump(full_config, f, indent=4)
                                    
                                    # 校验配置合法性
                                    if os.system(f"{SB_PATH} check -c {SB_CONF}.tmp") == 0:
                                        os.replace(SB_CONF + ".tmp", SB_CONF)
                                        os.system("systemctl restart sing-box")
                                        await ws.send(json.dumps({"type": "msg", "res": "Sync OK", "hash": self.get_config_state()['hash']}))
                                    else:
                                        await ws.send(json.dumps({"type": "msg", "res": "Config Error"}))
                                        if os.path.exists(SB_CONF + ".tmp"): os.remove(SB_CONF + ".tmp")
                                        
                        except asyncio.TimeoutError:
                            # 没收到指令，继续下一个心跳循环
                            continue
            except Exception as e:
                print(f"[{time.ctime()}] 连接异常: {e}，10秒后重试...")
                await asyncio.sleep(10)

if __name__ == "__main__":
    servant = ServantCore()
    asyncio.run(servant.main_loop())
EOF
    # 动态注入配置
    sed -i "s|REPLACE_URL|$FINAL_URL|; s|REPLACE_TOKEN|$M_TOKEN|" "$M_ROOT/agent/agent.py"
    
    # 部署并启动服务
    _deploy_service "hubnp-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 旗舰版被控已上线 (支持状态对齐与 Hybrid 同步)${PLAIN}"; pause_back
}
# --- [ 4. 链路诊断中心：动态端口感知版 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 旗舰诊断中心 (原生协议探测)${PLAIN}"
    
    # 定义通信端口变量（尝试从环境加载，否则默认 9339）
    [ -f "$M_ROOT/.env" ] && source "$M_ROOT/.env"
    WS_PORT=${M_WS_PORT:-9339}

    if [ -f "$M_ROOT/agent/agent.py" ]; then
        # 从代码中动态提取当前被控端实际运行的凭据
        A_URL=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_TK=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        
        echo -e "${GREEN}[ 当前 Agent 运行凭据 ]${PLAIN}"
        echo -e " 🔹 接入地址: ${SKYBLUE}$A_URL${PLAIN}"
        echo -e " 🔹 通信令牌: ${YELLOW}$A_TK${PLAIN}"
        echo -e "------------------------------------------------"
        
        # 物理探测逻辑：直接探测被控端配置的目标地址
        echo -ne " 👉 正在探测物理链路... "
        python3 -c "import websockets, asyncio; asyncio.run(websockets.connect('$A_URL', timeout=5))" >/dev/null 2>&1
        
        # 结果判定：0 为连接成功，1 为连接后握手失败（说明端口通了，但协议/Token不对），均为端口开放
        if [ $? -eq 0 ] || [ $? -eq 1 ]; then
             echo -e "${GREEN}OK${PLAIN} (端口已开放)"
             echo -e "${YELLOW}[提示]${PLAIN} 物理连接正常。如果面板仍无数据，请确认上述 Token 是否与主控一致。"
        else
             echo -e "${RED}FAIL${PLAIN}"
             echo -e "${RED}[错误]${PLAIN} 主控通信端口不可达，请检查防火墙或主控 $WS_PORT 端口是否开启。"
        fi
    else
        echo -e "${RED}[错误]${PLAIN} 本机未发现 Agent 记录，请先执行安装。"
    fi
    pause_back
}
# --- [ 0. Hub-Next Panel 旗舰版主菜单 ] ---
main_menu() {
    while true; do
        clear
        # 实时检测主控物理运行状态
        local m_stat="${RED}○ OFFLINE (未运行)${PLAIN}"
        if [ -f "$M_ROOT/.env" ]; then
            if systemctl is-active --quiet hub-next-panel ; then
                m_stat="${GREEN}● ONLINE (核心在线)${PLAIN}"
            fi
        fi

        echo -e "${SKYBLUE}==================================================${PLAIN}"
        echo -e "      🛰️  ${SKYBLUE}Hub-Next Panel${PLAIN} ${WHITE}Ver 1.0 (Build 202512)${PLAIN}"
        echo -e "      系统状态: $m_stat  |  架构: $(uname -m)"
        echo -e "${SKYBLUE}==================================================${PLAIN}"
        
        echo -e " ${BLUE}[1]${PLAIN} ${WHITE}安装/更新系统主控 (保留配置升级)${PLAIN}"
        echo -e " ${BLUE}[2]${PLAIN} ${WHITE}部署/同步集群被控 (Agent 节点接入)${PLAIN}"
        echo -e " ${BLUE}[3]${PLAIN} ${GREEN}凭据管理中心 (看板/实时修改/自愈)${PLAIN}"
        echo -e " ${BLUE}[4]${PLAIN} ${WHITE}链路智能诊断中心 (全链路拨测中心)${PLAIN}"
        echo -e " ${BLUE}[5]${PLAIN} ${RED}深度清理中心 (物理抹除进程/环境)${PLAIN}"
        echo -e " ${BLUE}[0]${PLAIN} 退出管理脚本"
        echo -e "${SKYBLUE}==================================================${PLAIN}"
        
        # 动态显示快速访问地址
        if [ -f "$M_ROOT/.env" ]; then
            source "$M_ROOT/.env"
            local ip=$(curl -s4m 2 api.ipify.org || echo "本机IP")
            echo -e "${GRAY} ⚡ 快速入口: http://$ip:$M_PORT ${PLAIN}"
        fi
        
        echo -ne "\n${SKYBLUE}请选择操作编号: ${PLAIN}"
        read -r c

        case $c in
            1) 
                install_master 
                ;;
            2) 
                install_agent 
                ;;
            3) 
                # 调用升级后的看板修改一体化函数
                credential_center 
                ;;
            4) 
                smart_diagnostic 
                ;;
            5) 
                echo -e "${RED}！！！警告：此操作将物理抹除所有环境与配置 ！！！${PLAIN}"
                read -p "确认清理？(y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    env_cleaner
                    rm -rf "$M_ROOT"
                    rm -f /etc/systemd/system/hub-next-*
                    rm -f /etc/systemd/system/multiy-*
                    systemctl daemon-reload
                    echo -e "${GREEN}物理清理完成。${PLAIN}"
                    sleep 2
                    exit 0
                fi
                ;;
            0) 
                echo -e "${SKYBLUE}感谢使用 Hub-Next Panel。${PLAIN}"
                exit 0 
                ;;
            *) 
                echo -e "${RED}输入错误，请输入 0-5 之间的数字${PLAIN}"
                sleep 1
                ;;
        esac
    done
}
check_root; install_shortcut; main_menu
