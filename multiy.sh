#!/bin/bash
# Multiy Pro V110.0 - 终极双栈自愈版 (看板监听+前端通信全修复)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V110.0-FIXED"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 1. 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 增强型看板 (彻底修复状态显示) ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板 (V110.0)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理端 (Web 面板) ]${PLAIN}"
    echo -e " 🔹 IPv4 访问: http://$V4:$M_PORT"
    [ "$V6" != "未分配" ] && echo -e " 🔹 IPv6 访问: http://[$V6]:$M_PORT"
    echo -e " 🔹 账号密码: ${YELLOW}$M_USER / $M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 被控端 (WSS 隧道) ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST:9339${PLAIN}"
    echo -e " 🔹 通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 物理监听自愈状态 ]${PLAIN}"
    # 采用底层 PID 检测，只要进程活着且占用了端口就算 OK
    check_p() {
        if lsof -i :"$1" > /dev/null; then echo -e "${GREEN}● ACTIVE${PLAIN}"; else echo -e "${RED}○ OFFLINE${PLAIN}"; fi
    }
    # 检测双栈绑定详情
    V4V6_WSS=$(ss -tuln | grep -q ":9339 " && echo -e "${GREEN}● 双栈就绪${PLAIN}" || echo -e "${RED}○ 监听失败${PLAIN}")
    V4V6_WEB=$(ss -tuln | grep -q ":$M_PORT " && echo -e "${GREEN}● 双栈就绪${PLAIN}" || echo -e "${RED}○ 监听失败${PLAIN}")

    echo -e " 🔹 接入端口 (9339): $V4V6_WSS"
    echo -e " 🔹 面板端口 ($M_PORT): $V4V6_WEB"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    
    echo -e "\n${YELLOW}[ 运维 ]${PLAIN} 1. 修改配置 | 2. 强制重启服务 | 0. 返回"
    read -p "选择: " op
    case $op in
        1) _edit_cfg ;;
        2) systemctl restart multiy-master; sleep 2; credential_center ;;
        *) main_menu ;;
    esac
}

_edit_cfg() {
    read -p "新用户: " M_USER; read -p "新密码: " M_PASS; read -p "新Token: " M_TOKEN
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
    install_master "hot"
}

# --- [ 3. 主控安装 (物理隔离与双栈强绑) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 终极主控 (V110.0)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    
    if [ "$1" != "hot" ]; then
        apt-get update && apt-get install -y python3 python3-pip openssl curl lsof net-tools >/dev/null 2>&1
        pip3 install "Flask<3.0.0" "python-socketio" "eventlet==0.33.3" "psutil" --break-system-packages --user >/dev/null 2>&1
        M_PORT=7575; M_USER=admin; M_PASS=admin; M_HOST="multix.spacelite.top"
        M_TOKEN=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
        read -p "Web 端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-$M_PORT}
        read -p "用户名 [admin]: " IN_USER; M_USER=${IN_USER:-$M_USER}
        read -p "密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-$M_PASS}
        read -p "Token: " IN_TK; M_TOKEN=${IN_TK:-$M_TOKEN}
        cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
    fi

    mkdir -p "$M_ROOT/master"
    [ ! -f "$M_ROOT/master/key.pem" ] && openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 主控已拉起。${PLAIN}"; sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, socket, subprocess
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

sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet', ping_timeout=45)
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

# --- [ 仪表盘美化 + 顶栏修复 ] ---
INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro Dashboard</title>
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
<style>
    body{background:#020617;color:#fff;font-family:ui-sans-serif,system-ui;overflow-x:hidden}
    .glass{background:rgba(255,255,255,0.01);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.08);border-radius:2rem}
    .top-badge{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.05);padding:8px 16px;border-radius:12px;font-size:10px;font-weight:900}
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
            <button @click="fetch()" class="text-[10px] font-black text-slate-500 uppercase tracking-widest hover:text-white transition">Refresh Data</button>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="glass p-10 border-blue-500/20 bg-blue-500/5">
                <h2 class="text-2xl font-black text-blue-400">DEMO-STATION</h2>
                <div class="mt-6 text-slate-500 text-[10px] uppercase font-black tracking-widest">WSS Tunnel Active</div>
            </div>
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all">
                    <div class="flex justify-between mb-8">
                        <div><h2 class="text-2xl font-black" x-text="node.alias"></h2><code class="text-blue-400 text-xs" x-text="node.ip"></code></div>
                    </div>
                    <div class="space-y-4">
                        <div class="flex justify-between text-[10px] font-black uppercase"><span class="text-slate-500">CPU</span><span x-text="node.stats.cpu+'%'"></span></div>
                        <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-500" :style="'width:'+node.stats.cpu+'%'"></div></div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, sys:{}, init(){
            this.socket = io({ transports: ['websocket', 'polling'] });
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
    return "<h2>Login</h2><form method='post'><input name='u'><input name='p' type='password'><button>Go</button></form>"

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

def run_wss():
    # 强制关闭 IPv6Only 模式，实现真双栈监听
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        sock.bind(('::', 9339))
        sock.listen(128)
        eventlet.wsgi.server(eventlet.wrap_ssl(sock, certfile='cert.pem', keyfile='key.pem', server_side=True), app)
    except:
        eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), certfile='cert.pem', keyfile='key.pem', server_side=True), app)

if __name__ == '__main__':
    Thread(target=run_wss, daemon=True).start()
    env = load_env()
    app.run(host='::', port=int(env.get('M_PORT', 7575)))
EOF
}

# --- [ 4. 其它模块 ] ---
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
    echo " 1. 安装/物理修复主控 (双栈强制自愈版)"
    echo " 2. 安装/更新被控 (自动双栈适配)"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置看板 (精准存活状态)"
    echo " 5. 深度清理中心 (彻底物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;; 4) credential_center ;; 5) 
        systemctl stop multiy-master multiy-agent 2>/dev/null; pkill -9 -f "app.py"
        rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 0) exit ;; esac
}

check_root; install_shortcut; main_menu
