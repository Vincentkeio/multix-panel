#!/bin/bash
# MultiX V8.1 - 旗舰完整版 (功能全集成 | 服务管理 | 拨测系统)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 基础核心：环境预检
# ==========================================

get_ips() {
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || echo "N/A")
}

force_fix_env() {
    echo -e "${Y}[*] 正在同步系统依赖...${NC}"
    rm -f /var/lib/dpkg/lock* 2>/dev/null
    apt-get update -y >/dev/null 2>&1
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd docker.io --no-install-recommends >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
    
    echo -e "${Y}[*] 正在静默注入 Python 核心...${NC}"
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet >/dev/null 2>&1 || true
    echo -e "${G}✅ 环境自愈完成。${NC}"
}

# ==========================================
# 主控端核心 (Master)
# ==========================================

install_master() {
    echo -e "${G}[+] 启动主控安装向导...${NC}"
    read -p "设置 Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "管理账号 [admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "通讯 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    get_ips
    mkdir -p "${INSTALL_PATH}/master/db_data"
    docker rm -f 3x-ui-master 2>/dev/null
    docker run -d --name 3x-ui-master --restart always --network host -v ${INSTALL_PATH}/master/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
IPV4="$IPV4"
EOF

    # 完整 Python 主控逻辑 (含 Vue 仪表盘)
    cat > "${INSTALL_PATH}/master/app.py" <<'EOF'
import json, asyncio, time, psutil, os, subprocess, sqlite3
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 自动读取 .env
CONFIG = {}
if os.path.exists("../.env"):
    with open("../.env") as f:
        for l in f:
            if '=' in l:
                k, v = l.replace('"', '').split('=', 1)
                CONFIG[k.strip()] = v.strip()

app = Flask(__name__)
app.secret_key = CONFIG.get('M_TOKEN', 'secret')
AGENTS = {}
LOOP = None

HTML = """
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Panel</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>body { background: #0a0a0a; color: #eee; }</style>
</head>
<body class="p-8">
    <div id="app">
        <div class="flex justify-between items-center mb-10">
            <h1 class="text-2xl font-black text-blue-500 uppercase italic">MultiX V8.1 Dashboard</h1>
            <div class="text-xs font-mono bg-zinc-900 p-2 rounded border border-white/5">TOKEN: {{token}}</div>
        </div>
        
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div v-for="(info, ip) in agents" class="bg-zinc-900 border border-white/5 p-6 rounded-2xl">
                <div class="flex justify-between mb-4"><span class="font-bold">{{ip}}</span><span class="text-green-500 text-xs font-mono">ONLINE</span></div>
                <div class="space-y-2 text-sm text-zinc-400">
                    <div class="flex justify-between"><span>CPU</span><span class="text-zinc-100">{{info.stats.cpu}}%</span></div>
                    <div class="flex justify-between"><span>MEM</span><span class="text-zinc-100">{{info.stats.mem}}%</span></div>
                </div>
                <button @click="sync(ip)" class="w-full mt-4 py-2 bg-blue-600 rounded-lg text-xs font-bold hover:bg-blue-500">同步 Reality 配置</button>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const agents = ref({});
                const token = ref('{{token}}');
                const update = async () => {
                    const r = await fetch('/api/state');
                    const d = await r.json();
                    agents.value = d.agents;
                };
                const sync = async (ip) => {
                    const r = await fetch('/api/sync', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({ip})
                    });
                    const d = await r.json();
                    alert(d.msg);
                };
                onMounted(() => { update(); setInterval(update, 3000); });
                return { agents, token, sync };
            }
        }).mount('#app');
    </script>
</body>
</html>
"""

@app.route('/api/state')
def get_state():
    return jsonify({"agents": {ip: {"stats": info["stats"]} for ip, info in AGENTS.items()}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    target_ip = request.json.get('ip')
    if target_ip in AGENTS:
        # 构造一个示例 Reality 配置同步任务
        payload = json.dumps({
            "action": "sync_node",
            "token": CONFIG.get('M_TOKEN'),
            "data": {"remark": "MultiX-Sync", "port": 443, "protocol": "vless"}
        })
        asyncio.run_coroutine_threadsafe(AGENTS[target_ip]['ws'].send(payload), LOOP)
        return jsonify({"msg": "指令已发送"})
    return jsonify({"msg": "节点不在线"}), 404

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML, token=CONFIG.get('M_TOKEN'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == CONFIG.get('M_USER') and request.form['p'] == CONFIG.get('M_PASS'):
            session['logged'] = True
            return redirect('/')
    return '<form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form>'

async def ws_handler(websocket, path=None):
    ip = websocket.remote_address[0]
    try:
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'auth':
                if data.get('token') == CONFIG.get('M_TOKEN'):
                    AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
            elif data.get('type') == 'heartbeat':
                if ip in AGENTS: AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)
    start_server = websockets.serve(ws_handler, "0.0.0.0", 8888)
    LOOP.run_until_complete(start_server); LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=int(CONFIG.get('M_PORT', 7575)))
EOF

    control_master "restart"
    echo -e "${G}🎉 主控已就绪！管理地址: http://$IPV4:$M_PORT${NC}"
    read -p "按回车返回菜单..."
    show_menu
}

# ==========================================
# 被控端核心 (Agent)
# ==========================================

install_agent() {
    echo -e "${G}[+] 启动被控安装向导...${NC}"
    read -p "请输入主控 IP: " M_HOST
    read -p "请输入通讯 Token: " A_TOKEN
    
    mkdir -p ${INSTALL_PATH}/agent/db_data
    cat > "$CONFIG_FILE" <<EOF
TYPE="AGENT"
MASTER_HOST="$M_HOST"
M_TOKEN="$A_TOKEN"
EOF

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, time

MASTER = "${M_HOST}"
TOKEN = "${A_TOKEN}"

async def run_agent():
    uri = f"ws://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri) as ws:
                await ws.send(json.dumps({"token": TOKEN, "type": "auth"}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    await asyncio.sleep(5)
        except: await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    # 部署 Agent 容器
    docker rm -f 3x-ui multix-agent 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    
    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<'EOF'
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil
WORKDIR /app
COPY agent.py .
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-img . >/dev/null 2>&1
    docker run -d --name multix-agent --restart always --network host -v ${INSTALL_PATH}/agent:/app multix-agent-img
    
    echo -e "${G}✅ 被控端已上线！${NC}"
    read -p "按回车返回菜单..."
    show_menu
}

# ==========================================
# 服务管理与拨测
# ==========================================

control_master() {
    case $1 in
        "start") nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 & ;;
        "stop") pkill -9 -f app.py ;;
        "restart") pkill -9 -f app.py; nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 & ;;
    esac
    echo -e "${G}主控服务 $1 成功${NC}"
}

control_agent() {
    docker $1 multix-agent 3x-ui >/dev/null 2>&1
    echo -e "${G}被控服务 $1 成功${NC}"
}

check_connect() {
    source "$CONFIG_FILE"
    echo -e "${Y}正在拨测主控端 [$MASTER_HOST:8888]...${NC}"
    if nc -zv -w 3 $MASTER_HOST 8888 2>&1 | grep -q 'succeeded'; then
        echo -e "${G}网络层: 连通正常${NC}"
    else
        echo -e "${R}网络层: 无法连接 (请检查主控防火墙/安全组 8888 端口)${NC}"
    fi
}

# ==========================================
# 菜单系统
# ==========================================

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V8.1        "
    echo -e "   上帝视角 | 极速响应 | 完整版    "
    echo -e "${G}==================================${NC}"
    echo -e "1. 🚀 安装/重装 主控端 (Master)"
    echo -e "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "3. ⚙️  [主控] 启动 | 停止 | 重启"
    echo -e "4. 🛠️  [被控] 启动 | 停止 | 重启"
    echo -e "5. 🔍 [拨测] 检查 Agent -> Master 连通性"
    echo -e "----------------------------------"
    echo -e "7. 🧹 环境自愈 (解决卡死/依赖问题)"
    echo -e "9. 🗑️  完全卸载"
    echo -e "0. 退出"
    echo -e "${G}==================================${NC}"
    read -p "选择操作: " opt
    case $opt in
        1) force_fix_env; install_master ;;
        2) force_fix_env; install_agent ;;
        3) read -p "输入指令 (start/stop/restart): " cmd; control_master "$cmd"; read -p "继续..."; show_menu ;;
        4) read -p "输入指令 (start/stop/restart): " cmd; control_agent "$cmd"; read -p "继续..."; show_menu ;;
        5) check_connect; read -p "继续..."; show_menu ;;
        7) force_fix_env; read -p "修复完成..."; show_menu ;;
        9) docker rm -f 3x-ui multix-agent 3x-ui-master; rm -rf $INSTALL_PATH; exit 0 ;;
        *) exit 0 ;;
    esac
}

# 脚本入口
mkdir -p "$INSTALL_PATH"
show_menu
