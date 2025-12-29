#!/bin/bash
# Multiy Pro V108.0 - 终极全能旗舰版 (双栈自愈/功能全回装/配置动态修改)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V108.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 1. 基础工具函数 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 配置中心看板 (支持修改与分类显示) ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    # 物理读取防堆叠
    M_TOKEN=$(grep "^M_TOKEN=" "$M_ROOT/.env" | head -n 1 | cut -d"'" -f2)
    M_PORT=$(grep "^M_PORT=" "$M_ROOT/.env" | head -n 1 | cut -d"'" -f2)
    M_USER=$(grep "^M_USER=" "$M_ROOT/.env" | head -n 1 | cut -d"'" -f2)
    M_PASS=$(grep "^M_PASS=" "$M_ROOT/.env" | head -n 1 | cut -d"'" -f2)
    M_HOST=$(grep "^M_HOST=" "$M_ROOT/.env" | head -n 1 | cut -d"'" -f2)
    
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰级配置中心"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理端 (Web 面板) ]${PLAIN}"
    echo -e " 🔹 IPv4 访问: http://$V4:$M_PORT"
    [ "$V6" != "未分配" ] && echo -e " 🔹 IPv6 访问: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理账户: ${YELLOW}$M_USER${PLAIN} / 密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 被控端 (Agent 通信) ]${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}9339${PLAIN} (WSS 安全隧道)"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    echo -e " 🔹 目标域名: $M_HOST"
    
    echo -e "\n${GREEN}[ 3. 物理监听状态 (双栈监测) ]${PLAIN}"
    check_v4_p() { ss -4tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    check_v6_p() { ss -6tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    
    echo -e " 🔹 Web 端口 ($M_PORT): $(check_v4_p $M_PORT) (V4) / $(check_v6_p $M_PORT) (V6)"
    echo -e " 🔹 WSS 隧道 (9339): $(check_v4_p 9339) (V4) / $(check_v6_p 9339) (V6)"
    
    echo -e "\n${SKYBLUE}--------------------------------------------------${PLAIN}"
    echo -e " 1. 修改管理账户/密码"
    echo -e " 2. 修改通信 Token"
    echo -e " 3. 重启主控服务 (热重载)"
    echo -e " 0. 返回主菜单"
    read -p "选择操作: " sub_opt
    case $sub_opt in
        1) read -p "新用户: " M_USER; read -p "新密码: " M_PASS; _save_cfg; install_master "hot" ;;
        2) read -p "新 Token: " M_TOKEN; _save_cfg; install_master "hot" ;;
        3) install_master "hot" ;;
        *) main_menu ;;
    esac
}

_save_cfg() {
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
}

# --- [ 3. 主控安装与热重载 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (V108.0)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    
    # 环境校准
    if [ "$1" != "hot" ]; then
        apt-get update && apt-get install -y python3 python3-pip openssl curl iproute2 net-tools >/dev/null 2>&1
        pip3 install "Flask<3.0.0" "python-socketio" "eventlet==0.33.3" "psutil" "cryptography==38.0.4" "pyOpenSSL==22.1.0" --break-system-packages --user >/dev/null 2>&1
        
        # 初始化默认值
        M_PORT=7575; M_USER=admin; M_PASS=admin; M_HOST="multix.spacelite.top"
        M_TOKEN=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
        read -p "设置 Web 端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-$M_PORT}
        read -p "设置用户名 [admin]: " IN_USER; M_USER=${IN_USER:-$M_USER}
        read -p "设置密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-$M_PASS}
        read -p "设置 Token (回车随机): " IN_TK; M_TOKEN=${IN_TK:-$M_TOKEN}
        _save_cfg
    fi

    mkdir -p "$M_ROOT/master"
    [ ! -f "$M_ROOT/master/key.pem" ] && openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    if command -v ufw >/dev/null; then ufw allow 9339/tcp; ufw allow "$M_PORT"/tcp; ufw reload; fi
    echo -e "${GREEN}✅ 主控已拉起/重载。${PLAIN}"; sleep 2; credential_center
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
sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet', ping_timeout=35)
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

@sio.on('disconnect')
def disconnect(sid):
    if sid in AGENTS: del AGENTS[sid]; sio.emit('update_ui', AGENTS)

@app.route('/api/state')
def api_state(): return jsonify({"agents": AGENTS})

@app.route('/api/info')
def api_info():
    env = load_env()
    ip4 = subprocess.getoutput("curl -s4m 2 api.ipify.org || echo 'N/A'")
    ip6 = subprocess.getoutput("curl -s6m 2 api64.ipify.org || echo 'N/A'")
    return jsonify({"token": env.get('M_TOKEN'), "ip4": ip4, "ip6": ip6, "m_port": env.get('M_PORT')})

# --- [ 仪表盘：拟物化美化版 ] ---
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
            <div class="top-badge uppercase">V4: <span class="text-blue-400" x-text="sys.ip4 + ':' + sys.m_port"></span></div>
            <div class="top-badge uppercase">V6: <span class="text-blue-400" x-text="'['+sys.ip6+']:' + sys.m_port"></span></div>
        </div>
        <header class="flex justify-between items-end mb-16">
            <h1 class="text-6xl font-black italic tracking-tighter text-blue-600">MULTIY <span class="text-white">PRO</span></h1>
            <a href="/logout" class="bg-red-500/10 border border-red-500/20 text-red-500 px-8 py-3 rounded-2xl text-xs font-black transition">LOGOUT</a>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="glass p-10 border-blue-500/20 bg-blue-500/5">
                <h2 class="text-2xl font-black text-blue-400">DEMO-NODE</h2>
                <div class="mt-10 space-y-6">
                    <div class="progress-bg"><div class="h-full bg-blue-500 animate-pulse" style="width:35%"></div></div>
                    <div class="text-[10px] font-black uppercase text-slate-500 tracking-widest">Static Mock Active</div>
                </div>
            </div>
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all duration-300">
                    <div class="flex justify-between mb-10">
                        <div><h2 class="text-2xl font-black" x-text="node.alias"></h2><code class="text-blue-400 text-xs" x-text="node.ip"></code></div>
                        <span class="text-[9px] bg-white/5 px-4 py-2 rounded-xl font-bold" x-text="node.connected_at"></span>
                    </div>
                    <div class="space-y-8">
                        <div><div class="flex justify-between text-[10px] font-black mb-2 uppercase text-slate-500"><span>Processor</span><span class="text-blue-400" x-text="node.stats.cpu+'%'"></span></div>
                        <div class="progress-bg"><div class="h-full bg-blue-500 transition-all duration-700" :style="'width:'+node.stats.cpu+'%'"></div></div></div>
                        <div><div class="flex justify-between text-[10px] font-black mb-2 uppercase text-slate-500"><span>Memory</span><span class="text-purple-400" x-text="node.stats.mem+'%'"></span></div>
                        <div class="progress-bg"><div class="h-full bg-purple-500 transition-all duration-700" :style="'width:'+node.stats.mem+'%'"></div></div></div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, sys:{}, init(){
            this.socket = io();
            this.socket.on('update_ui', (data) => { this.agents = data; });
            this.fetch();
        }, async fetch(){
            try{ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents;
                 const i=await fetch('/api/info'); const si=await i.json(); this.sys=si; }catch(e){}
        }}}
    </script>
</body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env(); app.secret_key = env.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif"><form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:60px;border-radius:35px;border:1px solid rgba(255,255,255,0.1);width:340px;text-align:center"><h2 style="color:#3b82f6;font-size:2rem;font-weight:900;margin-bottom:40px;font-style:italic">MULTIY <span style="color:#fff">PRO</span></h2><input name="u" placeholder="Admin" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><input name="p" type="password" placeholder="Pass" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><button style="width:100%;padding:16px;background:#3b82f6;color:#fff;border:none;border-radius:15px;font-weight:900;cursor:pointer;margin-top:20px">ACCESS SYSTEM</button></form></body>"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

def run_wss():
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

# --- [ 4. 被控与诊断模块 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 被控 (V108.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控地址 (域名/IP): " M_HOST
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
    echo -e "${GREEN}✅ 被控端已启动。${PLAIN}"; pause_back
}

smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心 (V108.0)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
        if curl -sk --max-time 3 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
            echo -e "👉 隧道检测: ${GREEN}成功 (WSS 响应正常)${PLAIN}"
        else
            echo -e "👉 隧道检测: ${RED}失败 (请检查主控防火墙)${PLAIN}"
        fi
    else
        echo "未发现被控安装记录。"
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
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/物理修复主控 (双栈自愈旗舰版)"
    echo " 2. 安装/更新被控 (自动双栈适配)"
    echo " 3. 智能链路诊断中心 (测试连通性)"
    echo " 4. 凭据与配置看板 (实时监测/修改)"
    echo " 5. 深度清理中心 (彻底物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;; 4) credential_center ;; 5) 
        systemctl stop multiy-master multiy-agent 2>/dev/null; pkill -9 -f "app.py"
        rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 0) exit ;; esac
}

check_root; install_shortcut; main_menu
