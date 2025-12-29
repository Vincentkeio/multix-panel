#!/bin/bash
# Multiy Pro V105.0 - 旗舰双栈全功能版 (基于 V86.0 核心)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V105.0-FINAL"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
# 修复核心：确保返回函数稳固
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 凭据与配置看板 (标注分类 + 双栈监测) ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板 (双栈版)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 面板登录端口 (WEB 管理端) ]${PLAIN}"
    echo -e " 🔹 IPv4 地址: http://$V4:$M_PORT"
    [ "$V6" != "未分配" ] && echo -e " 🔹 IPv6 地址: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理账户: ${YELLOW}$M_USER${PLAIN} / 密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 被控接入凭据 (WSS 通信端) ]${PLAIN}"
    echo -e " 🔹 主控域名: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 物理监听状态 (双栈监测) ]${PLAIN}"
    # 精确检测双栈监听情况
    V4_WSS=$(ss -tuln | grep -q "0.0.0.0:9339" && echo -e "${GREEN}● IPv4 在线${PLAIN}" || echo -e "${RED}○ IPv4 离线${PLAIN}")
    V6_WSS=$(ss -tuln | grep -q "\[::\]:9339" && echo -e "${GREEN}● IPv6 在线${PLAIN}" || echo -e "${RED}○ IPv6 离线${PLAIN}")
    V4_WEB=$(ss -tuln | grep -q "0.0.0.0:$M_PORT" && echo -e "${GREEN}● 在线${PLAIN}" || echo -e "${RED}○ 离线${PLAIN}")
    
    echo -e " 🔹 接入隧道 (WSS): $V4_WSS / $V6_WSS"
    echo -e " 🔹 面板 Web (V4): $V4_WEB"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装逻辑 (修复 Token 堆叠) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (V105.0)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    
    echo -e "${YELLOW}正在校准环境与 SSL 库依赖...${PLAIN}"
    pip3 uninstall -y pyOpenSSL cryptography eventlet --break-system-packages >/dev/null 2>&1
    pip3 install "cryptography==38.0.4" "pyOpenSSL==22.1.0" "eventlet==0.33.3" "python-socketio" "Flask<3.0.0" "psutil" --break-system-packages --user >/dev/null 2>&1

    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板 Web 端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "管理用户名 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "自定义 Token (回车随机): " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}
    M_HOST="multix.spacelite.top"

    # 核心修复：物理隔离写入，解决堆叠故障
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    if command -v ufw >/dev/null; then ufw allow 9339/tcp; ufw allow "$M_PORT"/tcp; ufw reload; fi
    
    echo -e "${GREEN}✅ 部署完成。${PLAIN}"; sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, psutil, socket, subprocess
from flask import Flask, render_template_string, session, redirect, request, jsonify
from threading import Thread

def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l: k, v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

conf = load_env()
sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet', ping_timeout=30)
app = Flask(__name__)
app.wsgi_app = socketio.WSGIApp(sio, app.wsgi_app)
AGENTS = {}

@sio.on('auth')
def authenticate(sid, data):
    env = load_env()
    if data.get('token') == env.get('M_TOKEN'):
        AGENTS[sid] = {"alias": data.get('hostname', 'Node'), "stats": {"cpu":0,"mem":0}, "last_seen": time.time(), "ip": request.remote_addr, "connected_at": time.strftime("%H:%M:%S")}
        sio.emit('ready', {'msg': 'verified'}, room=sid)
        sio.emit('update_ui', AGENTS)
        return True
    return False

@sio.on('heartbeat')
def handle_heartbeat(sid, data):
    if sid in AGENTS:
        AGENTS[sid]['stats'] = data; AGENTS[sid]['last_seen'] = time.time()
        sio.emit('update_ui', AGENTS)

@app.route('/api/state')
def api_state(): return jsonify({"agents": AGENTS})

@app.route('/api/info')
def api_info():
    env = load_env()
    ip4 = subprocess.getoutput("curl -s4m 2 api.ipify.org || echo 'N/A'")
    ip6 = subprocess.getoutput("curl -s6m 2 api64.ipify.org || echo 'N/A'")
    return jsonify({"token": env.get('M_TOKEN'), "ip4": ip4, "ip6": ip6, "m_port": env.get('M_PORT')})

# --- [ 全功能美化 UI ] ---
INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
<style>
    body{background:#020617;color:#fff;font-family:ui-sans-serif,system-ui;overflow-x:hidden}
    .glass{background:rgba(255,255,255,0.01);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.08);border-radius:2rem}
    .top-badge{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.05);padding:8px 16px;border-radius:12px;font-size:10px;font-weight:900}
    .progress-bg{height:8px;background:rgba(255,255,255,0.05);border-radius:10px;overflow:hidden}
</style></head>
<body class="p-6 md:p-12" x-data="panel()" x-init="init()">
    <div class="max-w-7xl mx-auto">
        <div class="flex flex-wrap gap-4 mb-10">
            <div class="top-badge uppercase">Token: <span class="text-blue-400" x-text="sys.token"></span></div>
            <div class="top-badge">V4: <span class="text-blue-400" x-text="sys.ip4 + ':' + sys.m_port"></span></div>
            <div class="top-badge">V6: <span class="text-blue-400" x-text="'['+sys.ip6+']:' + sys.m_port"></span></div>
        </div>
        <header class="flex justify-between items-end mb-16">
            <h1 class="text-6xl font-black italic tracking-tighter text-blue-600">MULTIY <span class="text-white">PRO</span></h1>
            <a href="/logout" class="bg-red-500 hover:bg-red-600 text-white px-8 py-3 rounded-2xl text-xs font-black transition">LOGOUT</a>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="glass p-10 border-blue-500/20 bg-blue-500/5">
                <h2 class="text-2xl font-black text-blue-400">DEMO-NODE-01</h2>
                <div class="mt-8 space-y-4">
                    <div class="flex justify-between text-[10px] font-black uppercase text-slate-500"><span>Processor</span><span class="text-blue-400">24%</span></div>
                    <div class="progress-bg"><div class="h-full bg-blue-500" style="width:24%"></div></div>
                </div>
            </div>
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all">
                    <div class="flex justify-between mb-10">
                        <div><h2 class="text-2xl font-black" x-text="node.alias"></h2><code class="text-blue-400 text-xs" x-text="node.ip"></code></div>
                        <span class="text-[9px] bg-white/5 px-4 py-2 rounded-xl font-bold" x-text="node.connected_at"></span>
                    </div>
                    <div class="space-y-8">
                        <div><div class="flex justify-between text-[10px] font-black uppercase mb-2 text-slate-500"><span>CPU</span><span class="text-blue-400" x-text="node.stats.cpu+'%'"></span></div>
                        <div class="progress-bg"><div class="h-full bg-blue-500 transition-all duration-700" :style="'width:'+node.stats.cpu+'%'"></div></div></div>
                        <div><div class="flex justify-between text-[10px] font-black uppercase mb-2 text-slate-500"><span>MEM</span><span class="text-purple-400" x-text="node.stats.mem+'%'"></span></div>
                        <div class="progress-bg"><div class="h-full bg-purple-500 transition-all duration-700" :style="'width:'+node.stats.mem+'%'"></div></div></div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { 
            agents:{}, sys:{}, init(){
                this.socket = io();
                this.socket.on('update_ui', (data) => { this.agents = data; });
                this.fetch();
            }, async fetch(){
                try{ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents;
                     const i=await fetch('/api/info'); const si=await i.json(); this.sys=si; }catch(e){}
            } 
        } }
    </script>
</body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env(); app.secret_key = env.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return render_template_string("<h3>Login</h3><form method='post'><input name='u'><input name='p' type='password'><button>Go</button></form>")

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

def run_wss():
    # 物理强行双栈监听
    try:
        sock = eventlet.listen(('::', 9339), family=socket.AF_INET6)
        eventlet.wsgi.server(eventlet.wrap_ssl(sock, certfile='cert.pem', keyfile='key.pem', server_side=True), app)
    except:
        eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), certfile='cert.pem', keyfile='key.pem', server_side=True), app)

if __name__ == '__main__':
    Thread(target=run_wss, daemon=True).start()
    env = load_env()
    app.run(host='::', port=int(env.get('M_PORT', 7575)))
EOF
}

# --- [ 3. 被控逻辑 (维持 V86.0) ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 被控 (V105.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名/IP: " M_HOST
    read -p "2. 通信令牌 (Token): " M_TOKEN
    pip3 install "python-socketio[client]" "psutil" --break-system-packages --user >/dev/null 2>&1
    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import socketio, time, psutil, socket, ssl
sio = socketio.Client(ssl_verify=False)
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"
@sio.event
def connect(): sio.emit('auth', {'token': TOKEN, 'hostname': socket.gethostname()})
def send_heartbeat():
    while True:
        if sio.connected:
            stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
            sio.emit('heartbeat', stats)
        time.sleep(8)
if __name__ == "__main__":
    while True:
        try: sio.connect(f"https://{MASTER}:9339"); send_heartbeat()
        except: time.sleep(5)
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控已启动。${PLAIN}"; pause_back
}

# --- [ 4. 连通性测试 (全找回) ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心 (修复版)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
        if curl -sk --max-time 3 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
            echo -e "👉 隧道检测: ${GREEN}成功 (WSS 响应正常)${PLAIN}"
        else
            echo -e "👉 隧道检测: ${RED}失败 (端口不可达)${PLAIN}"
        fi
    fi
    pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=${NAME}
After=network.target
[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 物理修复并安装主控 (V105.0 稳定版)"
    echo " 2. 安装/更新被控 (自动双栈适配)"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置看板 (全功能详情)"
    echo " 5. 深度清理中心 (彻底抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;; 4) credential_center ;; 5) 
        systemctl stop multiy-master multiy-agent 2>/dev/null; pkill -9 -f "app.py"
        rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 0) exit ;; esac
}

check_root; install_shortcut; main_menu
