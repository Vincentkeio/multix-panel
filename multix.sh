#!/bin/bash

# ==============================================================================
# MultiX Pro Script V70.2 (Syntax & Syntax Fix)
# Fix 1: Removed hidden special characters/full-width spaces causing syntax errors.
# Fix 2: Locked 'EOF' to prevent shell interference with Python decorators (@).
# Fix 3: Maintained all V70.1 features (Dual-stack, UI Unlocked, Smart Repair).
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V70.2"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 0. 快捷命令 ] ---
install_shortcut() {
    rm -f /usr/bin/multix
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}[INFO]${PLAIN} multix 快捷命令已更新"
}
install_shortcut

# --- [ 1. 基础函数 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} 必须 Root 运行！" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() {
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 环境修复 ] ---
fix_dual_stack() {
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf; fi
    sysctl -p >/dev/null 2>&1
}

fix_apt_sources() {
    if ! apt-get update -y >/dev/null 2>&1; then
        apt-get update --allow-releaseinfo-change >/dev/null 2>&1
        if grep -q "bullseye-backports" /etc/apt/sources.list; then
            sed -i '/bullseye-backports/s/^/#/' /etc/apt/sources.list
            sed -i '/bullseye-backports/s/^/#/' /etc/apt/sources.list.d/*.list 2>/dev/null
        fi
        apt-get update -y
    fi
}

install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} 检查依赖..."
    check_sys
    if [[ "${RELEASE}" == "debian" || "${RELEASE}" == "ubuntu" ]]; then
        fix_apt_sources
        apt-get install -y python3 python3-pip curl wget socat tar openssl git netcat-openbsd ntpdate
    elif [[ "${RELEASE}" == "centos" ]]; then 
        yum install -y epel-release python3 python3-devel python3-pip curl wget socat tar openssl git nc ntpdate
    fi
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1 || \
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        if ! curl -fsSL https://get.docker.com | bash; then
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        fi
        systemctl enable docker; systemctl start docker
    fi
    fix_dual_stack
}

# --- [ 3. 深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️  警告：此操作将删除所有 MultiX 组件！${PLAIN}"; read -p "确认? [y/N]: " confirm
    [[ "$confirm" != "y" ]] && return
    systemctl stop multix-master 2>/dev/null
    systemctl disable multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    docker stop multix-agent 3x-ui 2>/dev/null; docker rm -f multix-agent 3x-ui 2>/dev/null
    pkill -9 -f "master/app.py"; pkill -9 -f "agent/agent.py"
    rm -rf "$M_ROOT"
    echo -e "${GREEN}[INFO]${PLAIN} 清理完成"; pause_back
}

# --- [ 4. 服务管理 ] ---
service_manager() {
    while true; do
        clear; echo -e "${SKYBLUE}⚙️ 服务管理${PLAIN}"
        echo " 1. 启动 主控端"
        echo " 2. 停止 主控端"
        echo " 3. 重启 主控端"
        echo " 4. 查看 主控状态"
        echo "----------------"
        echo " 5. 重启 被控端 (Agent)"
        echo " 6. 查看 被控日志 (Debug)"
        echo " 0. 返回"
        read -p "选择: " s
        case $s in
            1) systemctl start multix-master && echo "Done" ;; 2) systemctl stop multix-master && echo "Done" ;;
            3) systemctl restart multix-master && echo "Done" ;; 4) systemctl status multix-master -l --no-pager ;;
            5) docker restart multix-agent && echo "Done" ;; 6) docker logs multix-agent --tail 50 ;; 0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

# --- [ 5. 凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据管理中心${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        M_T=$(grep 'M_TOKEN=' $M_ROOT/.env | cut -d"'" -f2)
        M_P=$(grep 'M_PORT=' $M_ROOT/.env | cut -d"'" -f2)
        M_U=$(grep 'M_USER=' $M_ROOT/.env | cut -d"'" -f2)
        M_W=$(grep 'M_PASS=' $M_ROOT/.env | cut -d"'" -f2)
        get_public_ips
        echo -e "${YELLOW}>>> 主控管理入口 <<<${PLAIN}"
        [[ "$IPV4" != "N/A" ]] && echo -e "IPv4 地址: ${GREEN}http://${IPV4}:${M_P}${PLAIN}"
        [[ "$IPV6" != "N/A" ]] && echo -e "IPv6 地址: ${GREEN}http://[${IPV6}]:${M_P}${PLAIN}"
        echo -e "管理用户: ${SKYBLUE}${M_U}${PLAIN} | 管理密码: ${SKYBLUE}${M_W}${PLAIN}"
        echo -e "通信令牌: ${YELLOW}${M_T}${PLAIN}"
    fi
    AGENT_HOST="未配置"; AGENT_TOKEN="未配置"
    if [ -f "$AGENT_CONF" ]; then 
        AGENT_HOST=$(grep 'AGENT_HOST=' "$AGENT_CONF" | cut -d"'" -f2)
        AGENT_TOKEN=$(grep 'AGENT_TOKEN=' "$AGENT_CONF" | cut -d"'" -f2)
    fi
    echo -e "\n${YELLOW}>>> 被控端 (Agent) 配置 <<<${PLAIN}"
    echo -e "连接目标: ${GREEN}${AGENT_HOST}${PLAIN} | 连接令牌: ${SKYBLUE}${AGENT_TOKEN}${PLAIN}"
    echo "--------------------------------"
    echo " 1. 修改主控配置 (端口/密码/Token)"
    echo " 2. 修改被控连接 (重设目标/Token)"
    echo " 0. 返回"
    read -p "选择: " c
    if [[ "$c" == "1" ]]; then
        read -p "新端口: " np; M_PORT=${np:-$M_P}
        read -p "新用户: " nu; M_USER=${nu:-$M_U}
        read -p "新密码: " nw; M_PASS=${nw:-$M_W}
        read -p "新Token: " nt; M_TOKEN=${nt:-$M_T}
        echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
        systemctl restart multix-master; echo "主控已重启"
    elif [[ "$c" == "2" ]]; then
        read -p "新主控IP/域名: " nh; AGENT_HOST=${nh:-$AGENT_HOST}
        read -p "新连接令牌: " ntk; AGENT_TOKEN=${ntk:-$AGENT_TOKEN}
        echo "AGENT_HOST='$AGENT_HOST'" > "$AGENT_CONF"; echo "AGENT_TOKEN='$AGENT_TOKEN'" >> "$AGENT_CONF"
        if [ -d "$M_ROOT/agent" ]; then
            generate_agent_py "$AGENT_HOST" "$AGENT_TOKEN"
            docker restart multix-agent; echo -e "${GREEN}被控已同步重启${PLAIN}"
        fi
    fi
    pause_back
}

# --- [ 辅助：生成 Agent 代码 ] ---
generate_agent_py() {
    local host=$1; local token=$2
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform, time
MASTER = "$host"; TOKEN = "$token"; DB_PATH = "/app/db_share/x-ui.db"
def log(msg): print(f"[Agent] {msg}", flush=True)
def get_xui_ver():
    if os.path.exists(DB_PATH): return "Installed"
    return "Not Found"
def smart_sync_db(data):
    try:
        if not os.path.exists(DB_PATH): log("DB missing"); return False
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        columns = [info[1] for info in cursor.fetchall()]
        base = {'user_id': 1, 'up': 0, 'down': 0, 'total': 0, 'remark': data.get('remark'), 'enable': 1, 'expiry_time': 0, 'listen': '', 'port': data.get('port'), 'protocol': data.get('protocol'), 'settings': data.get('settings'), 'stream_settings': data.get('stream_settings'), 'tag': 'multix', 'sniffing': data.get('sniffing', '{}')}
        valid = {k: v for k, v in base.items() if k in columns}
        nid = data.get('id')
        if nid:
            set_c = ", ".join([f"{k}=?" for k in valid.keys()])
            cursor.execute(f"UPDATE inbounds SET {set_c} WHERE id=?", list(valid.values()) + [nid])
        else:
            keys = ", ".join(valid.keys()); ph = ", ".join(["?"]*len(valid))
            cursor.execute(f"INSERT INTO inbounds ({keys}) VALUES ({ph})", list(valid.values()))
        conn.commit(); conn.close(); log(f"Synced Node: {data.get('remark')}"); return True
    except Exception as e: log(f"DB Error: {e}"); return False
async def run():
    target = MASTER
    if ":" in target and not target.startswith("[") and not target[0].isalpha(): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    log(f"Connecting to {uri} ...")
    while True:
        try:
            async with websockets.connect(uri, ping_interval=20, open_timeout=20) as ws:
                log("Connected! Auth..."); await ws.send(json.dumps({"token": TOKEN}))
                await ws.send(json.dumps({"type": "heartbeat", "data": {"cpu":0,"mem":0,"os":platform.system(),"xui":get_xui_ver()}, "nodes": []}))
                while True:
                    nodes = []
                    try:
                        if os.path.exists(DB_PATH):
                            conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                            cur.execute("SELECT id, remark, port, protocol, settings, stream_settings FROM inbounds")
                            for r in cur.fetchall():
                                try: nodes.append({"id": r[0], "remark": r[1], "port": r[2], "protocol": r[3], "settings": json.loads(r[4]), "stream_settings": json.loads(r[5])})
                                except: pass
                            conn.close()
                    except: pass
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent), "os": platform.system(), "xui": get_xui_ver()}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5); task = json.loads(msg)
                        if task.get('action') == 'sync_node': os.system("docker restart 3x-ui"); smart_sync_db(task['data']); os.system("docker restart 3x-ui")
                    except: continue
        except Exception as e: log(f"Connect Fail: {e}"); await asyncio.sleep(5)
asyncio.run(run())
EOF
}

# --- [ 3. 连通性测试 + 智能修复 ] ---
smart_network_repair() {
    echo -e "\n${YELLOW}🔧 正在执行智能网络修复...${PLAIN}"
    ip link set dev eth0 mtu 1280 2>/dev/null
    ip link set dev ens3 mtu 1280 2>/dev/null
    ntpdate pool.ntp.org >/dev/null 2>&1
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}✅ 修复完成！${PLAIN}"; pause_back
}

connection_test() {
    echo -e "${SKYBLUE}📡 智能连通性测试${PLAIN}"
    if [ -f "$AGENT_CONF" ]; then
        AGENT_HOST=$(grep 'AGENT_HOST=' "$AGENT_CONF" | cut -d"'" -f2)
        AGENT_TOKEN=$(grep 'AGENT_TOKEN=' "$AGENT_CONF" | cut -d"'" -f2)
    else
        read -p "IP/Domain: " AGENT_HOST; read -p "Token: " AGENT_TOKEN
    fi
    [ -z "$AGENT_HOST" ] && return
    nc -zv -w 5 "$AGENT_HOST" 8888
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] TCP 连接失败。${PLAIN}"
    else
        echo -e "${GREEN}[PASS] TCP 连接成功。${PLAIN}"
    fi
    pause_back
}

# --- [ 6. 主控安装 ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master
    echo -e "${SKYBLUE}>>> 主控配置${PLAIN}"
    read -p "端口 [默认 7575]: " IN_PORT; M_PORT=${IN_PORT:-7575}
    read -p "用户 [默认 admin]: " IN_USER; M_USER=${IN_USER:-admin}
    read -p "密码 [默认 admin]: " IN_PASS; M_PASS=${IN_PASS:-admin}
    RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "Token [默认随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-$RAND}
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
    _write_master_app_py
    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
User=root
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    echo -e "${GREEN}✅ 主控部署成功${PLAIN}"; credential_center
}

_write_master_app_py() {
    # V70.2 FIX: 使用单引号锁定 EOF，彻底避免 Bash 解析 Python 语法
    cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, subprocess, base64, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

logging.basicConfig(level=logging.ERROR)

def load_conf():
    c = {}
    try:
        with open('/opt/multix_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

CONF = load_conf()
M_PORT = int(CONF.get('M_PORT', 7575))
M_USER = CONF.get('M_USER', 'admin')
M_PASS = CONF.get('M_PASS', 'admin')
M_TOKEN = CONF.get('M_TOKEN', 'error')

app = Flask(__name__)
app.secret_key = M_TOKEN

AGENTS = {"local-demo": {"alias": "Demo Node", "stats": {"cpu": 15, "mem": 40, "os": "Demo OS", "xui": "v2.x.x"}, "nodes": [{"id": 1, "remark": "Demo-VLESS", "port": 443, "protocol": "vless", "settings": {"clients":[{"id":"demo-uuid"}]}, "stream_settings": {"network":"ws", "security":"tls"}}], "is_demo": True}}
LOOP_GLOBAL = None

def get_sys_info():
    try:
        v4 = os.popen("curl -s4 api.ipify.org || echo 'N/A'").read().strip()
        v6 = os.popen("curl -s6 api64.ipify.org || echo 'N/A'").read().strip()
        return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": v4, "ipv6": v6}
    except: return {"cpu":0,"mem":0,"ipv4":"N/A","ipv6":"N/A"}

@app.route('/api/gen_key', methods=['POST'])
def gen_key():
    t = request.json.get('type')
    try:
        if t == 'reality':
            out = subprocess.check_output("xray x25519 || echo 'Private key: x Public key: x'", shell=True).decode()
            return jsonify({"private": out.split("Private key:")[1].split()[0].strip(), "public": out.split("Public key:")[1].split()[0].strip()})
        elif t == 'ss-128': return jsonify({"key": base64.b64encode(os.urandom(16)).decode()})
        elif t == 'ss-256': return jsonify({"key": base64.b64encode(os.urandom(32)).decode()})
    except: return jsonify({"key": "Error", "private": "", "public": ""})

HTML_T = """
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
    <style>body{background:#050505;font-family:'Segoe UI',sans-serif;padding-top:20px}.card{background:#111;border:1px solid #333;transition:0.3s}.card:hover{border-color:#0d6efd;transform:translateY(-2px)}.status-dot{width:10px;height:10px;border-radius:50%;display:inline-block}.status-online{background:#198754;box-shadow:0 0 5px #198754}.status-offline{background:#dc3545}.header-token{font-family:monospace;color:#ffc107;font-size:0.9rem;margin-left:10px}.stat-box{font-size:0.8rem;color:#888;background:#1a1a1a;padding:5px 10px;border-radius:4px;border:1px solid #333}.table-dark{background:#111}.table-dark td,.table-dark th{border-color:#333}</style>
</head>
<body>
<div id="error-banner" class="alert alert-danger shadow-lg fw-bold" style="display:none;position:fixed;top:10px;left:50%;transform:translateX(-50%);z-index:1050;"></div>
<div class="container">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div><h2 class="fw-bold fst-italic text-primary mb-0">MultiX <span class="text-white">Pro</span></h2><div class="text-secondary font-monospace small mt-1"><span class="badge bg-secondary">v4</span> <span id="ipv4">...</span> | <span class="badge bg-primary">v6</span> <span id="ipv6">...</span><span class="header-token" title="Master Token"><i class="bi bi-key"></i> TK: {{ token }}</span></div></div>
        <div class="d-flex gap-2 align-items-center"><span class="badge bg-dark border border-secondary p-2">CPU: <span id="cpu">0</span>%</span><span class="badge bg-dark border border-secondary p-2">MEM: <span id="mem">0</span>%</span><a href="/logout" class="btn btn-outline-danger btn-sm fw-bold">LOGOUT</a></div>
    </div>
    <div class="row g-4" id="node-list"></div>
</div>
<div class="modal fade" id="configModal" tabindex="-1"><div class="modal-dialog modal-lg modal-dialog-centered"><div class="modal-content" style="background:#0a0a0a; border:1px solid #333;"><div class="modal-header border-bottom border-secondary"><h5 class="modal-title fw-bold" id="modalTitle">Node Manager</h5><button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body" id="view-list"><div class="d-flex justify-content-between mb-3"><span class="text-secondary">Inbound Nodes</span><button class="btn btn-sm btn-success fw-bold" onclick="toAddMode()"><i class="bi bi-plus-lg"></i> ADD NODE</button></div><table class="table table-dark table-hover table-sm text-center align-middle"><thead><tr><th>ID</th><th>Remark</th><th>Port</th><th>Proto</th><th>Action</th></tr></thead><tbody id="tbl-body"></tbody></table></div><div class="modal-body" id="view-edit" style="display:none"><button class="btn btn-sm btn-outline-secondary mb-3" onclick="toListView()"><i class="bi bi-arrow-left"></i> Back</button><form id="nodeForm"><input type="hidden" id="nodeId"><div class="row g-3"><div class="col-md-6"><label class="form-label text-secondary small fw-bold">REMARK</label><input type="text" class="form-control bg-dark text-white border-secondary" id="remark"></div><div class="col-md-6"><label class="form-label text-secondary small fw-bold">PORT</label><input type="number" class="form-control bg-dark text-white border-secondary" id="port"></div><div class="col-md-6"><label class="form-label text-secondary small fw-bold">PROTOCOL</label><select class="form-select bg-dark text-white border-secondary" id="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option><option value="shadowsocks">Shadowsocks</option></select></div><div class="col-md-6 group-uuid"><label class="form-label text-secondary small fw-bold">UUID</label><div class="input-group"><input type="text" class="form-control bg-dark text-white border-secondary font-monospace" id="uuid"><button class="btn btn-outline-secondary" type="button" onclick="genUUID()">Gen</button></div></div><div class="col-md-6 group-ss" style="display:none"><label class="form-label text-secondary small fw-bold">CIPHER</label><select class="form-select bg-dark text-white border-secondary" id="ssCipher"><option value="aes-256-gcm">aes-256-gcm</option><option value="2022-blake3-aes-128-gcm">2022-blake3-aes-128-gcm</option></select></div><div class="col-md-6 group-ss" style="display:none"><label class="form-label text-secondary small fw-bold">PASSWORD</label><div class="input-group"><input type="text" class="form-control bg-dark text-white border-secondary font-monospace" id="ssPass"><button class="btn btn-outline-secondary" type="button" onclick="genSSKey()">Gen</button></div></div><div class="col-12"><hr class="border-secondary"></div><div class="col-md-6"><label class="form-label text-secondary small fw-bold">NETWORK</label><select class="form-select bg-dark text-white border-secondary" id="network"><option value="tcp">TCP</option><option value="ws">WebSocket</option></select></div><div class="col-md-6"><label class="form-label text-secondary small fw-bold">SECURITY</label><select class="form-select bg-dark text-white border-secondary" id="security"><option value="none">None</option><option value="tls">TLS</option><option value="reality">Reality</option></select></div><div class="col-12 group-reality" style="display:none"><div class="p-3 border border-primary rounded bg-dark bg-opacity-50"><div class="row g-2"><div class="col-6"><small class="text-primary">Dest</small><input class="form-control form-control-sm bg-black text-white border-secondary" id="dest" value="www.microsoft.com:443"></div><div class="col-6"><small class="text-primary">SNI</small><input class="form-control form-control-sm bg-black text-white border-secondary" id="serverNames" value="www.microsoft.com"></div><div class="col-12"><small class="text-primary">Private Key</small><div class="input-group input-group-sm"><input class="form-control bg-black text-white border-secondary font-monospace" id="privKey"><button class="btn btn-primary" type="button" onclick="genReality()">Gen</button></div></div><div class="col-12"><small class="text-primary">Public Key</small><input class="form-control font-monospace form-control-sm bg-black text-white border-secondary" id="pubKey" readonly></div><div class="col-12"><small class="text-primary">Short IDs</small><input class="form-control form-control-sm bg-black text-white border-secondary font-monospace" id="shortIds"></div></div></div></div><div class="col-12 group-ws" style="display:none"><div class="p-2 border border-secondary rounded"><div class="row g-2"><div class="col-6"><small>Path</small><input class="form-control form-control-sm bg-black text-white border-secondary" id="wsPath" value="/"></div><div class="col-6"><small>Host</small><input class="form-control form-control-sm bg-black text-white border-secondary" id="wsHost"></div></div></div></div></div></form><div class="mt-3 text-end"><button type="button" class="btn btn-primary fw-bold" id="saveBtn">Save & Sync</button></div></div></div></div></div>
{% raw %}
<script>let AGENTS={},ACTIVE_IP='',CURRENT_NODES=[];function updateState(){$.get('/api/state',function(d){$('#error-banner').hide();$('#cpu').text(d.master.stats.cpu);$('#mem').text(d.master.stats.mem);$('#ipv4').text(d.master.ipv4);$('#ipv6').text(d.master.ipv6);AGENTS=d.agents;renderGrid()}).fail(function(){$('#error-banner').text('Lost').fadeIn()})}function renderGrid(){$('#node-list').empty();for(const[ip,a]of Object.entries(AGENTS)){const s=(a.is_demo||a.stats.cpu!==undefined)?'status-online':'status-offline';const c=`<div class="col-md-6 col-lg-4"><div class="card h-100 p-3"><div class="d-flex justify-content-between align-items-center mb-2"><h5 class="fw-bold text-white mb-0 text-truncate">${a.alias||'Unknown'}</h5><span class="status-dot ${s}"></span></div><div class="small text-secondary font-monospace mb-3">${ip}</div><div class="d-flex flex-wrap gap-2 mb-3"><span class="stat-box">OS: ${a.stats.os||'N/A'}</span><span class="stat-box">3X: ${a.stats.xui||'N/A'}</span><span class="stat-box">CPU: ${a.stats.cpu||0}%</span><span class="stat-box">MEM: ${a.stats.mem||0}%</span></div><button class="btn btn-primary w-100 fw-bold" onclick="openManager('${ip}')">MANAGE NODES (${a.nodes?a.nodes.length:0})</button></div></div>`;$('#node-list').append(c)}}function openManager(ip){ACTIVE_IP=ip;CURRENT_NODES=AGENTS[ip].nodes||[];toListView();$('#configModal').modal('show')}function toListView(){$('#view-edit').hide();$('#view-list').show();$('#modalTitle').text(`Nodes on ${ACTIVE_IP}`);const t=$('#tbl-body');t.empty();if(CURRENT_NODES.length===0)t.append('<tr><td colspan="5">No nodes.</td></tr>');else CURRENT_NODES.forEach((n,i)=>{t.append(`<tr><td><span class="badge bg-secondary font-monospace">${n.id}</span></td><td>${n.remark}</td><td class="font-monospace text-info">${n.port}</td><td>${n.protocol}</td><td><button class="btn btn-sm btn-outline-primary" onclick="toEditMode(${i})"><i class="bi bi-pencil-square"></i></button></td></tr>`)})}function toAddMode(){$('#view-list').hide();$('#view-edit').show();$('#modalTitle').text('Add Node');resetForm()}function toEditMode(i){$('#view-list').hide();$('#view-edit').show();$('#modalTitle').text('Edit Node');loadForm(CURRENT_NODES[i])}function updateFormVisibility(){const p=$('#protocol').val(),n=$('#network').val(),s=$('#security').val();$('.group-ss,.group-uuid,.group-reality,.group-ws').hide();if(p==='shadowsocks'){$('.group-ss').show()}else{$('.group-uuid').show()}if(s==='reality')$('.group-reality').show();if(n==='ws')$('.group-ws').show()} $('#protocol,#network,#security').change(updateFormVisibility);function genUUID(){$('#uuid').val(crypto.randomUUID())}function genSSKey(){const t=$('#ssCipher').val().includes('256')?'ss-256':'ss-128';$.ajax({url:'/api/gen_key',type:'POST',contentType:'application/json',data:JSON.stringify({type:t}),success:function(d){$('#ssPass').val(d.key)}})}function genReality(){$.ajax({url:'/api/gen_key',type:'POST',contentType:'application/json',data:JSON.stringify({type:'reality'}),success:function(d){$('#privKey').val(d.private);$('#pubKey').val(d.public)}})}function resetForm(){$('#nodeForm')[0].reset();$('#nodeId').val('');$('#protocol').val('vless');$('#network').val('tcp');$('#security').val('reality');genUUID();genReality();updateFormVisibility()}function loadForm(n){try{const s=n.settings||{},ss=n.stream_settings||{};$('#nodeId').val(n.id);$('#remark').val(n.remark);$('#port').val(n.port);$('#protocol').val(n.protocol);if(n.protocol==='shadowsocks'){$('#ssCipher').val(s.method);$('#ssPass').val(s.password)}else{$('#uuid').val(s.clients?s.clients[0].id:'')}$('#network').val(ss.network||'tcp');$('#security').val(ss.security||'none');if(ss.realitySettings){$('#dest').val(ss.realitySettings.dest);$('#serverNames').val((ss.realitySettings.serverNames||[]).join(','));$('#privKey').val(ss.realitySettings.privateKey);$('#pubKey').val(ss.realitySettings.publicKey);$('#shortIds').val((ss.realitySettings.shortIds||[]).join(','))}if(ss.wsSettings){$('#wsPath').val(ss.wsSettings.path);$('#wsHost').val(ss.wsSettings.headers?.Host)}updateFormVisibility()}catch(e){resetForm()}}$('#saveBtn').click(function(){const p=$('#protocol').val(),n=$('#network').val(),s=$('#security').val();let clients=[];if(p!=='shadowsocks')clients.push({id:$('#uuid').val(),flow:(s==='reality'&&p==='vless')?'xtls-rprx-vision':'',email:'u@mx.com'});let stream={network:n,security:s};if(s==='reality')stream.realitySettings={dest:$('#dest').val(),privateKey:$('#privKey').val(),publicKey:$('#pubKey').val(),shortIds:$('#shortIds').val().split(','),serverNames:$('#serverNames').val().split(','),fingerprint:'chrome'};if(n==='ws')stream.wsSettings={path:$('#wsPath').val(),headers:{Host:$('#wsHost').val()}};let settings=p==='shadowsocks'?{method:$('#ssCipher').val(),password:$('#ssPass').val(),network:'tcp,udp'}:{clients,decryption:'none'};const pl={id:$('#nodeId').val()||null,remark:$('#remark').val(),port:parseInt($('#port').val()),protocol:p,settings:JSON.stringify(settings),stream_settings:JSON.stringify(stream),sniffing:JSON.stringify({enabled:true,destOverride:["http","tls","quic"]}),total:0,expiry_time:0};const btn=$(this);btn.prop('disabled',true).text('Saving...');$.ajax({url:'/api/sync',type:'POST',contentType:'application/json',data:JSON.stringify({ip:ACTIVE_IP,config:pl}),success:function(r){$('#configModal').modal('hide');btn.prop('disabled',false).text('Save');if(r.status==='demo_ok')alert('Demo Mock OK');else alert('Synced!')},error:function(){btn.prop('disabled',false).text('Fail');alert('Error')}})});$(document).ready(function(){updateState();setInterval(updateState,3000)});</script>
{% endraw %}
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T, token=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS: session['logged'] = True; return redirect('/')
    return """<body style='background:#000;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh'><form method='post'><input name='u' placeholder='User' required><input type='password' name='p' placeholder='Pass' required><button>Login</button></form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

@app.route('/api/state')
def api_state():
    s = get_sys_info()
    return jsonify({"master": {"ipv4": s['ipv4'], "ipv6": s['ipv6'], "stats": {"cpu": s['cpu'], "mem": s['mem']}}, "agents": AGENTS})

@app.route('/api/sync', methods=['POST'])
def api_sync():
    d = request.json
    target = d.get('ip')
    if target in AGENTS:
        if AGENTS[target].get('is_demo'): return jsonify({"status": "demo_ok"})
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": d.get('config')})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"status": "sent"})
    return jsonify({"status": "offline"}), 404

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {}, "nodes": []}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data', {})
                    AGENTS[ip]['nodes'] = d.get('nodes', [])
                    AGENTS[ip]['alias'] = d.get('data', {}).get('os', 'Node')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m(): await websockets.serve(ws_handler, "0.0.0.0", 8888)
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

# --- [ 7. 被控安装 ] ---
install_agent() {
    install_dependencies; 
    if ! command -v docker &> /dev/null; then echo -e "${RED}[FATAL] Docker Error${PLAIN}"; exit 1; fi
    mkdir -p $M_ROOT/agent
    if [ ! -d "/etc/x-ui" ]; then
        docker run -d --name 3x-ui --restart always --network host -v /etc/x-ui:/etc/x-ui -v /etc/x-ui/bin:/usr/local/x-ui/bin mhsanaei/3x-ui:latest >/dev/null 2>&1
        sleep 5
    fi
    echo -e "${SKYBLUE}>>> 被控配置${PLAIN}"
    read -p "主控域名/IP: " IN_HOST; read -p "Token: " IN_TOKEN
    echo -e "1. 自动 (Auto)\n2. 强制 IPv4\n3. 强制 IPv6"
    read -p "选择 [1-3]: " NET_OPT
    case "$NET_OPT" in
        2) IN_HOST=$(getent hosts "$IN_HOST" | awk '{print $1}' | grep -E '^[0-9]+\.' | head -n 1 || echo "$IN_HOST") ;;
        3) IN_HOST=$(getent hosts "$IN_HOST" | awk '{print $1}' | grep ":" | head -n 1 || echo "$IN_HOST") ;;
    esac
    echo "AGENT_HOST='$IN_HOST'" > "$AGENT_CONF"; echo "AGENT_TOKEN='$IN_TOKEN'" >> "$AGENT_CONF"
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    generate_agent_py "$IN_HOST" "$IN_TOKEN"
    cd $M_ROOT/agent; docker build -t multix-agent-v70 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v70
    echo -e "${GREEN}✅ 被控启动完成${PLAIN}"; pause_back
}

# --- [ 9. 主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V70.2 Dual-Stack Fixed)${PLAIN}"
    echo " 1. 安装 主控端"
    echo " 2. 安装 被控端"
    echo " 3. 智能连通测试"
    echo " 4. 被控重启"
    echo " 5. 深度清理"
    echo " 6. 环境修复"
    echo " 7. 凭据管理"
    echo " 8. 实时日志"
    echo " 9. 运维工具"
    echo " 10. 服务管理"
    echo " 11. 智能网络修复 (MTU/Time/FW)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 
        2) install_agent ;;
        3) connection_test ;;
        4) docker restart multix-agent; pause_back ;;
        5) deep_cleanup ;;
        6) install_dependencies; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) sys_tools ;; 
        10) service_manager ;; 
        11) smart_network_repair ;;
        0) exit 0 ;; 
        *) main_menu ;;
    esac
}
main_menu
