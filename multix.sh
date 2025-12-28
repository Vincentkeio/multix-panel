#!/bin/bash
# MultiX V6.8 - 旗舰终极版 (彻底修复依赖死锁 & 函数置顶加载)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 模块 A：底层函数置顶 (必须放在开头，防止command not found)
# ==========================================

get_ips() {
    echo -e "${Y}[*] 正在嗅探双栈网络环境...${NC}"
    # 预设变量，防止 curl 失败导致脚本报错
    IPV4="N/A"; IPV6="N/A"
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || curl -4 -s --connect-timeout 5 https://ifconfig.me || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || curl -6 -s --connect-timeout 5 https://ifconfig.me || echo "N/A")
    echo -e "IPv4: ${G}$IPV4${NC} | IPv6: ${G}$IPV6${NC}"
}

force_fix_env() {
    echo -e "${Y}[*] 正在执行系统环境深度自愈...${NC}"
    # 1. 彻底清除冲突源 (防止再次死锁)
    apt-get purge -y containerd.io docker-ce docker-ce-cli runc 2>/dev/null
    
    # 2. 修复 DPKG 状态
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock
    dpkg --configure -a
    apt-get install -f -y

    # 3. 安装系统组件 (使用自带 docker.io 避坑)
    echo -e "${Y}[*] 正在同步系统依赖...${NC}"
    apt-get update -y
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd build-essential docker.io --no-install-recommends
    
    systemctl start docker && systemctl enable docker

    # 4. 强灌 Python 库 (解决 Externally Managed 环境问题)
    echo -e "${Y}[*] 正在注入 Python 环境...${NC}"
    python3 -m pip install --upgrade pip --break-system-packages --quiet 2>/dev/null
    python3 -m pip install flask websockets psutil cryptography docker --break-system-packages --quiet 2>/dev/null
}

# ==========================================
# 模块 B：主控端业务逻辑 (Master)
# ==========================================

install_master() {
    echo -e "${G}[+] 启动 V6.8 主控安装向导...${NC}"
    read -p "设置管理 Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "管理账号 [admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "通讯 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    get_ips
    mkdir -p "${INSTALL_PATH}/master"

    # 写入配置，变量全部加双引号
    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
IPV4="$IPV4"
IPV6="$IPV6"
EOF

    # 生成主控核心 app.py (变量引用已加引号保护)
    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, secrets, os, base64
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

def generate_x25519():
    priv_key = x25519.X25519PrivateKey.generate()
    pub_key = priv_key.public_key()
    priv_bytes = priv_key.private_bytes(encoding=serialization.Encoding.Raw,format=serialization.PrivateFormat.Raw,encryption_algorithm=serialization.NoEncryption())
    pub_bytes = pub_key.public_bytes(encoding=serialization.Encoding.Raw,format=serialization.PublicFormat.Raw)
    return base64.b64encode(priv_bytes).decode(), base64.b64encode(pub_bytes).decode()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>MultiX V6.8 Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style> body { font-family: 'Inter', sans-serif; background: #050505; } </style>
</head>
<body class="text-slate-300">
    <div class="flex h-screen">
        <aside class="w-64 bg-zinc-950 border-r border-white/5 p-6 flex flex-col">
            <h1 class="text-xl font-bold text-white italic">🛰️ MultiX V6.8</h1>
            <nav class="mt-10 space-y-2 flex-1">
                <button onclick="location.reload()" class="w-full text-left p-3 rounded-xl bg-white/5 hover:bg-white/10 transition">📊 仪表盘</button>
            </nav>
            <div class="pt-4 border-t border-white/5"><a href="/logout" class="text-zinc-500 hover:text-red-400">🚪 退出系统</a></div>
        </aside>
        <main class="flex-1 p-8 overflow-y-auto">
            <div class="flex justify-between items-center mb-10">
                <h2 class="text-2xl font-bold text-white">集群节点 ({{ agents_count }})</h2>
                <div class="text-xs font-mono bg-zinc-900 border border-white/5 px-4 py-2 rounded-full">Token: <span class="text-yellow-500">{{ auth_token }}</span></div>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                {% for ip, info in agents.items() %}
                <div class="bg-zinc-900/50 border border-white/5 rounded-2xl p-6">
                    <div class="flex justify-between mb-4"><span>{{ ip }}</span><span class="h-2 w-2 rounded-full bg-green-500 animate-pulse"></span></div>
                    <div class="flex gap-4 mb-6">
                        <div class="flex-1 bg-black/40 rounded p-2 text-center text-xs">CPU<br>{{ info.stats.cpu }}%</div>
                        <div class="flex-1 bg-black/40 rounded p-2 text-center text-xs">MEM<br>{{ info.stats.mem }}%</div>
                    </div>
                    <button onclick="openEditor('{{ ip }}')" class="w-full py-2 bg-blue-600 rounded-xl text-sm font-bold">⚙️ 管理节点</button>
                </div>
                {% endfor %}
            </div>
        </main>
    </div>

    <div id="editorModal" class="fixed inset-0 bg-black/90 backdrop-blur-sm hidden items-center justify-center z-50">
        <div class="bg-zinc-900 border border-white/10 w-[450px] rounded-3xl p-8">
            <h3 class="text-xl font-bold text-white mb-6">同步到: <span id="target_ip_display" class="text-blue-400"></span></h3>
            <div class="space-y-4">
                <input type="text" id="node_uuid" placeholder="UUID" class="w-full bg-black border border-white/5 rounded-xl p-3 text-sm">
                <input type="text" id="node_priv" placeholder="Reality 私钥" class="w-full bg-black border border-white/5 rounded-xl p-3 text-sm">
                <div class="flex gap-4">
                    <button onclick="closeEditor()" class="flex-1 py-3 bg-zinc-800 rounded-2xl">取消</button>
                    <button onclick="saveSync()" class="flex-1 py-3 bg-blue-600 rounded-2xl">同步</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        let curIP = "";
        const $ = (id) => document.getElementById(id);
        function openEditor(ip) { curIP = ip; $('target_ip_display').innerText = ip; $('editorModal').style.display = 'flex'; }
        function closeEditor() { $('editorModal').style.display = 'none'; }
        async function saveSync() {
            const data = { ip: curIP, uuid: $('node_uuid').value, priv: $('node_priv').value, port: 443, remark: "V6.8_REALITY" };
            const r = await fetch('/send', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
            const res = await r.json(); alert(res.msg); closeEditor();
        }
    </script>
</body>
</html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == "$M_USER" and request.form['p'] == "$M_PASS":
            session['logged'] = True
            return redirect('/')
    return '<form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    req = request.json
    node_data = {
        "remark": f"MX-{req['remark']}", "port": int(req['port']), "protocol": "vless",
        "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}], "decryption": "none"}),
        "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": req['priv'], "shortIds": ["abcdef123456"]}}),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 指令已送达"})
    return jsonify({"msg": "❌ 小鸡离线"}), 404

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth_msg).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        async for msg in websocket:
            d = json.loads(msg)
            if d.get('type') == 'heartbeat': AGENTS[ip]['stats'] = d['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws_loop():
    global LOOP
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)
    srv = websockets.serve(ws_server, "0.0.0.0", 8888)
    LOOP.run_until_complete(srv); LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=$M_PORT)
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    echo -e "${G}🎉 主控部署成功！访问地址见配置信息。${NC}"
}

# ==========================================
# 模块 C：被控端逻辑 (Agent)
# ==========================================

install_agent() {
    echo -e "${G}--- 被控端安装 (SQL嗅探版) ---${NC}"
    read -p "请输入主控 域名/IP: " M_HOST
    read -p "请输入通讯 Token: " A_TOKEN
    
    get_ips
    mkdir -p ${INSTALL_PATH}/agent/db_data
    cat > "$CONFIG_FILE" <<EOF
TYPE="AGENT"
MASTER_HOST="$M_HOST"
M_TOKEN="$A_TOKEN"
LOCAL_IPV4="$IPV4"
LOCAL_IPV6="$IPV6"
EOF

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, subprocess, time, socket

MASTER_HOST = "${M_HOST}"
TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_fields():
    try:
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        fields = [row[1] for row in cursor.fetchall()]
        conn.close(); return fields
    except: return []

async def handle_task(task):
    try:
        if task.get('action') == 'sync_node':
            subprocess.run("docker stop 3x-ui", shell=True)
            fields = get_db_fields()
            data = task['data']
            valid_data = {k: v for k, v in data.items() if k in fields}
            conn = sqlite3.connect(DB_PATH)
            keys = ", ".join(valid_data.keys()); placeholders = ", ".join(["?"] * len(valid_data))
            conn.execute(f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})", list(valid_data.values()))
            conn.commit(); conn.close()
            subprocess.run("docker start 3x-ui", shell=True)
    except Exception as e: print(f"Error: {e}")

async def run_agent():
    uri = f"ws://{MASTER_HOST}:8888"
    while True:
        try:
            async with websockets.connect(uri, family=socket.AF_UNSPEC) as ws:
                await ws.send(json.dumps({"token": TOKEN, "fields": get_db_fields()}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    await handle_task(json.loads(msg))
        except: await asyncio.sleep(5)
if __name__ == '__main__': asyncio.run(run_agent())
EOF

    docker pull ghcr.io/mhsanaei/3x-ui:latest
    docker rm -f 3x-ui 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image
    echo -e "${G}✅ 被控端部署完成！${NC}"
}

# ==========================================
# 模块 D：入口与菜单
# ==========================================

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V6.8        "
    echo -e "   环境修复 | 绝对置顶 | 旗舰版    "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看配置凭据"
    echo "6. 📡 连通性拨测"
    echo "7. 🧹 深度清理与冲突修复 (必选)"
    echo "9. 🗑️  完全卸载"
    echo "0. 退出"
    echo -e "${G}==================================${NC}"
    read -p "选择操作: " choice
    case $choice in
        1) force_fix_env && install_master ;;
        2) force_fix_env && install_agent ;;
        3) clear; [ -f "$CONFIG_FILE" ] && { source "$CONFIG_FILE"; echo "Token: $M_TOKEN"; echo "IPv4: $IPV4 | IPv6: $IPV6"; } || echo "未发现配置"; read -p "回车继续..." ;;
        6) clear; [ -f "$CONFIG_FILE" ] && { source "$CONFIG_FILE"; ping -c 2 -W 3 $MASTER_HOST && echo "网络OK" || echo "网络断开"; nc -zv $MASTER_HOST 8888 && echo "端口开放" || echo "端口关闭"; } || echo "请先安装"; read -p "按键继续..." ;;
        7) force_fix_env ;;
        9) docker rm -f 3x-ui multix-agent; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
}

mkdir -p "$INSTALL_PATH"
show_menu
