#!/bin/bash
# Multiy Pro V135.0-ULTIMATE - 终极全功能旗舰版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 深度清理中心：含 UI 物理重置版 ] ---
env_cleaner() {
    echo -e "${YELLOW}>>> 正在执行环境物理级大扫除 (含旧版残余抹除)...${PLAIN}"
    
    # 1. 停止并禁用所有相关服务名 (含旧版 multix 兼容)
    systemctl stop multiy-master multiy-agent multix* 2>/dev/null
    systemctl disable multiy-master multiy-agent multix* 2>/dev/null
    
    # 2. 移除系统服务文件并刷新守护进程
    rm -f /etc/systemd/system/multiy-* /etc/systemd/system/multix-* 2>/dev/null
    systemctl daemon-reload
    
    # 3. 强制杀死残留进程 (精准匹配路径关键字)
    echo -e "${YELLOW}正在清理旧进程残留...${PLAIN}"
    pkill -9 -f "master/app.py" 2>/dev/null
    pkill -9 -f "agent/agent.py" 2>/dev/null
    pkill -9 -f "multix" 2>/dev/null
    pkill -9 -f "multiy" 2>/dev/null
    
    # 4. 定点强杀端口占用 (面板与通信端口)
    for port in 7575 9339; do
        local pid=$(lsof -t -i:"$port" 2>/dev/null)
        if [ ! -z "$pid" ]; then
            echo -e "${YELLOW}发现端口 $port 被进程 $pid 占用，强制释放...${PLAIN}"
            kill -9 "$pid" 2>/dev/null
        fi
    done

    # 5. 【核心重构】物理重置 UI 缓存目录结构
    # 这一步彻底解决了“清单删除但文件残留”导致的安装报错问题
    echo -e "${YELLOW}正在执行 UI 物理路径重置...${PLAIN}"
    rm -rf "$M_ROOT/master/templates"
    rm -rf "$M_ROOT/master/static"
    # 重建标准旗舰版目录结构
    mkdir -p "$M_ROOT/master/templates/modals"
    mkdir -p "$M_ROOT/master/static"

    # 6. 更新 Python 环境依赖与基础工具
    echo -e "${YELLOW}正在校准 Python 环境依赖...${PLAIN}"
    if ! command -v lsof &> /dev/null; then
        apt-get update && apt-get install -y lsof >/dev/null 2>&1
    fi
    # 卸载旧冲突库，重装三件套
    python3 -m pip uninstall -y python-socketio eventlet python-engineio 2>/dev/null
    python3 -m pip install --upgrade flask websockets psutil --break-system-packages 2>/dev/null
    
    echo -e "${GREEN}>>> 物理大扫除完成，环境与 UI 结构已就绪。${PLAIN}"
}
# --- [ 1. 凭据与配置详情看板 ] ---
# --- [ 1. 凭据中心看板模块 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}[错误]${PLAIN} 尚未安装主控！" && pause_back && return
    source "$M_ROOT/.env"
    
    # 获取实时 IP
    V4=$(curl -s4m 2 api.ipify.org || echo "N/A")
    V6=$(curl -s6m 2 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    
    echo -e "${GREEN}[ 1. 管理面板入口 ]${PLAIN}"
    echo -e " 🔹 IPv4 访问: http://$V4:$M_PORT"
    echo -e " 🔹 IPv6 访问: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理账号: ${YELLOW}$M_USER${PLAIN}"
    echo -e " 🔹 管理密码: ${YELLOW}$M_PASS${PLAIN}"
    
# 动态获取通信端口变量，如果脚本中未定义则兜底 9339
    WS_PORT=${M_WS_PORT:-9339}

    echo -e "\n${GREEN}[ 2. Agent 接入配置 (原生 WS) ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}$WS_PORT${PLAIN}"
    echo -e " 🔹 通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 双栈监听物理状态 ]${PLAIN}"
    
# --- [ 提升版：双栈解耦物理探测 ] ---
    check_net_stat() {
        local port=$1
        local family=$2
        
        # 使用 ss 分别提取 IPv4 和 IPv6 栈的真实监听状态
        local has_v4=$(ss -lnpt4 | grep -q ":$port " && echo "yes" || echo "no")
        local has_v6=$(ss -lnpt6 | grep -q ":$port " && echo "yes" || echo "no")

        if [ "$family" == "v4" ]; then
            # 只要 IPv4 栈有监听，或者 IPv6 栈处于双栈合一 (::) 模式，v4 就算 OK
            if [ "$has_v4" == "yes" ] || ss -lnpt | grep -q ":::$port"; then
                echo -ne "${GREEN}● IPv4 OK${PLAIN}"
            else
                echo -ne "${RED}○ IPv4 OFF${PLAIN}"
            fi
        else
            # 显式检查 IPv6 协议栈是否有监听
            if [ "$has_v6" == "yes" ]; then
                echo -ne "${GREEN}● IPv6 OK${PLAIN}"
            else
                echo -ne "${RED}○ IPv6 OFF${PLAIN}"
            fi
        fi
    }

    # 定义通信端口变量（对齐主控逻辑）
    WS_PORT=${M_WS_PORT:-9339}

    echo -ne " 🔹 面板服务 ($M_PORT): "
    check_net_stat "$M_PORT" "v4"
    echo -ne "  "
    check_net_stat "$M_PORT" "v6"
    echo ""
    
    echo -ne " 🔹 通信服务 ($WS_PORT): "
    check_net_stat "$WS_PORT" "v4"
    echo -ne "  "
    check_net_stat "$WS_PORT" "v6"
    echo ""
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    
    # --- [ 深度自诊逻辑 ] ---
    if ss -lnpt | grep -q ":::$M_PORT"; then
        echo -e "${GREEN}[状态] 检测到双栈(::)监听模式。${PLAIN}"
        echo -e "${GREEN}[状态] 内核已自动将 IPv4 流量映射至 IPv6 协议栈。${PLAIN}"
    elif ss -lnpt | grep -q "0.0.0.0:$M_PORT"; then
        echo -e "${YELLOW}[状态] 仅检测到纯 IPv4 监听。IPv6 访问可能受限。${PLAIN}"
    else
        echo -e "${RED}[告警] 端口 $M_PORT 未处于监听状态，请检查进程。${PLAIN}"
    fi

    pause_back
}

# --- [ 补全缺失的服务部署函数 ] ---
_deploy_service() {
    local name=$1
    local cmd=$2
    local workdir=$(dirname "$cmd")
    
    echo -e "${YELLOW}>>> 正在注册系统服务: ${name}${PLAIN}"
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

# --- [ 2. 主控安装：旗舰加固版 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (双栈自愈版)${PLAIN}"
    apt-get install -y python3-pip
    
    # 1. 物理环境预优化：强制开启内核双栈监听映射 (修复 IPv4 OFF 问题)
    echo -e "${YELLOW}>>> 优化系统内核双栈通信参数...${PLAIN}"
    sysctl -w net.ipv6.bindv6only=0 >/dev/null 2>&1

    # 2. 物理目录强制初始化
    mkdir -p "$M_ROOT/master/static"
    mkdir -p "$M_ROOT/master/templates/modals"

echo -e "\n${YELLOW}--- 交互式设置 (回车使用默认值) ---${PLAIN}"
    
    # 1. 面板端口交互：增加数字合法性校验
    read -p "1. 面板 Web 端口 [默认 7575]: " M_PORT
    if [[ ! "$M_PORT" =~ ^[0-9]+$ ]] || [ "$M_PORT" -lt 1 ] || [ "$M_PORT" -gt 65535 ]; then
        M_PORT=7575
        echo -e "${YELLOW}[提示] 输入端口无效或为空，已回退至默认: 7575${PLAIN}"
    fi

    read -p "2. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "3. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    read -p "4. 主控公网地址: " M_HOST; M_HOST=${M_HOST:-$(curl -s4 api.ipify.org)}
    
    # 5. Token 生成与交互
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "5. 通信令牌 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}

    # --- [ 写入环境变量：确保持久化 ] ---
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
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
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    echo -e "${GREEN}✅ 旗舰版主控部署完成。${PLAIN}"; sleep 2; credential_center
}
# --- [ 后端核心逻辑：旗舰全功能固化版 - 集成凭据与端口同步 ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess, psutil, platform, random, threading, socket, base64
from flask import Flask, request, jsonify, send_from_directory, render_template

# 1. 基础配置
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
M_ROOT = "/opt/multiy_mvp"
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

# --- [ 2. 状态路由：支持主控硬件与配置同步 ] ---
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

# --- [ 核心修复：添加凭据物理更新 API ] ---
@app.route('/api/update_admin', methods=['POST'])
def update_admin():
    try:
        d = request.get_json()
        if request.headers.get('Authorization') != TOKEN:
            return jsonify({"status": "fail", "msg": "Unauthorized"}), 403

        # 1. 物理写入 .env 文件确保持久化
        with open(ENV_PATH, 'w', encoding='utf-8') as f:
            f.write(f"M_USER='{d.get('user')}'\n")
            f.write(f"M_PASS='{d.get('pass')}'\n")
            f.write(f"M_TOKEN='{d.get('token')}'\n")
            f.write(f"M_PORT='{d.get('port', '7575')}'\n")
            f.write(f"M_WS_PORT='{d.get('ws_port', '9339')}'\n")
            f.write(f"M_HOST='{env.get('M_HOST', '0.0.0.0')}'\n")

        # 2. 异步重启服务以应用新端口和凭据
        def restart_srv():
            import time
            time.sleep(1)
            os.system("systemctl restart multiy-master")
        import threading
        threading.Thread(target=restart_srv).start()

        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500
# --- [ 4. 节点管理路由 ] ---
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

# --- [ 5. 静态、订阅与密钥 ] ---
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

# --- [ WebSocket 实时通信 ] ---
async def ws_handler(ws):
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    node_uuid = None
    try:
        async for m in ws:
            d = json.loads(m)
            if d.get('token') != TOKEN: continue
            node_uuid = d.get('node_id')
            db = load_db()
            if node_uuid not in db:
                db[node_uuid] = {"hostname": d.get('hostname', 'Node'), "order": len(db)+1, "ip": ws.remote_address[0], "hidden": False, "alias": ""}
                save_db(db)
            AGENTS_LIVE[node_uuid] = {"metrics": d.get('metrics'), "session": sid}
    except: pass
    finally: WS_CLIENTS.pop(sid, None)

async def main():
    curr_env = load_env()
    web_p = int(curr_env.get('M_PORT', 7575))
    ws_p = int(curr_env.get('M_WS_PORT', 9339))
    
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
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰被控 (Hybrid 状态对齐版)${PLAIN}"
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
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
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
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro Beta ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新主控 (不执行强制清理)"
    echo " 2. 安装/更新被控 (不执行强制清理)"
    echo " 3. 实时凭据与监听看板"
    echo " 4. 链路智能诊断中心"
    echo " 5. 深度清理中心 (物理抹除旧进程/端口/环境)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;;  # 直接进入安装，不再调用 env_cleaner
        2) install_agent ;;   # 直接进入安装
        3) credential_center ;;
        4) smart_diagnostic ;;
        5) env_cleaner; rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 
        0) exit ;; 
    esac
}
check_root; install_shortcut; main_menu
