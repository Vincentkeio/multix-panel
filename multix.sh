#!/bin/bash
# MultiX V4.0 - 全能 Dashboard 版 (主控增强 + 实时监控 + 智能修复)

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V4.0        "
    echo -e "    可视化仪表盘 | 智能自愈系统    "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 🗑️  卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 📡 安装/重装 被控端 (Agent + 3x-ui)"
    echo "4. 🗑️  卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "7. 🔧 智能一键修复 (不删数据，解决死机)"
    echo "----------------------------------"
    echo "5. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [1-7]: " choice
}

# --- 智能修复逻辑 ---
smart_repair() {
    echo -e "${Y}[*] 启动智能修复流程...${NC}"
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    for port in 2053 2096; do
        PID=$(lsof -t -i:$port)
        if [ ! -z "$PID" ] && ! ps -p $PID -o comm= | grep -qi "docker"; then
            kill -9 $PID 2>/dev/null
        fi
    done
    DB_FILE="${INSTALL_PATH}/agent/db_data/x-ui.db"
    if [ -f "$DB_FILE" ]; then
        rm -f "${DB_FILE}-wal" "${DB_FILE}-shm"
        sqlite3 "$DB_FILE" "UPDATE settings SET value = '2053' WHERE name = 'webPort';"
    fi
    docker restart 3x-ui multix-agent 2>/dev/null
    echo -e "${G}✅ 修复尝试完成！${NC}"
    sleep 2
}

# --- 安装主控端 (Dashboard 增强版) ---
install_master() {
    echo -e "${G}[+] 启动 V4.0 主控安装向导...${NC}"
    read -p "设置管理 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "设置管理员账号 [默认 admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置管理员密码 [默认 admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip psmisc curl lsof
    pip3 install flask websockets psutil --break-system-packages --quiet || pip3 install flask websockets psutil --quiet

    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, secrets, os
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

def get_master_stats():
    net_io = psutil.net_io_counters()
    return {
        "cpu": psutil.cpu_percent(),
        "mem": psutil.virtual_memory().percent,
        "disk": psutil.disk_usage('/').percent,
        "net_sent": round(net_io.bytes_sent / 1024 / 1024, 2),
        "net_recv": round(net_io.bytes_recv / 1024 / 1024, 2),
        "uptime": int(time.time() - psutil.boot_time()) // 3600
    }

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>MultiX V4.0 Dashboard</title>
    <style>
        body { background: #0f111a; color: #a6adbb; font-family: 'Segoe UI', sans-serif; margin: 0; display: flex; }
        .sidebar { width: 240px; background: #1a1c27; height: 100vh; padding: 20px; border-right: 1px solid #2a2d3e; }
        .main { flex: 1; padding: 30px; overflow-y: auto; }
        .card { background: #1a1c27; border-radius: 12px; padding: 20px; margin-bottom: 20px; border: 1px solid #2a2d3e; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 20px; }
        .stat-val { font-size: 24px; color: #fff; font-weight: bold; }
        .stat-label { font-size: 12px; color: #646b7b; text-transform: uppercase; }
        .btn { background: #5865f2; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; transition: 0.3s; }
        .btn:hover { background: #4752c4; }
        .badge { background: #232733; padding: 4px 10px; border-radius: 4px; font-size: 12px; color: #00ff00; }
        .agent-card { border-left: 4px solid #5865f2; }
        input, select { background: #0f111a; border: 1px solid #2a2d3e; color: #fff; padding: 8px; border-radius: 4px; width: 100%; margin: 10px 0; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 100; }
        .modal-content { background: #1a1c27; margin: 5% auto; padding: 30px; width: 450px; border-radius: 15px; border: 1px solid #2a2d3e; }
    </style>
</head>
<body>
    <div class="sidebar">
        <h2 style="color:#fff">🛰️ MultiX V4.0</h2>
        <p style="color:#5865f2">分布式管理系统</p>
        <hr style="border:0; border-top:1px solid #2a2d3e; margin: 20px 0;">
        <div style="cursor:pointer; padding:10px 0; color:#fff">📊 运行概览</div>
        <div style="cursor:pointer; padding:10px 0;">🛡️ 安全设置</div>
        <div style="cursor:pointer; padding:10px 0;">📜 系统日志</div>
        <div style="margin-top:50px"><a href="/logout" style="color:#ff4d4d; text-decoration:none">🚪 退出登录</a></div>
    </div>
    <div class="main">
        <h3>📊 主控机系统状态 (Dashboard)</h3>
        <div class="grid">
            <div class="card">
                <div class="stat-label">CPU 使用率</div>
                <div class="stat-val">{{ master.cpu }}%</div>
            </div>
            <div class="card">
                <div class="stat-label">内存使用率</div>
                <div class="stat-val">{{ master.mem }}%</div>
            </div>
            <div class="card">
                <div class="stat-label">磁盘占用</div>
                <div class="stat-val">{{ master.disk }}%</div>
            </div>
            <div class="card">
                <div class="stat-label">运行时间</div>
                <div class="stat-val">{{ master.uptime }} 小时</div>
            </div>
        </div>

        <h3>📡 节点管理 (在线: {{ agents_count }})</h3>
        <div class="grid">
            {% for ip, info in agents.items() %}
            <div class="card agent-card">
                <div style="display:flex; justify-content:space-between">
                    <span style="color:#fff; font-weight:bold">{{ ip }}</span>
                    <span class="badge">Online</span>
                </div>
                <p style="font-size:13px">CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}%</p>
                <button class="btn" onclick="openEdit('{{ ip }}')">配置节点</button>
            </div>
            {% endfor %}
            {% if agents_count == 0 %}
            <div class="card" style="grid-column: 1 / -1; text-align: center; color: #646b7b;">
                目前暂无被控小鸡在线，请先安装被控端。
            </div>
            {% endif %}
        </div>
    </div>

    <div id="editModal" class="modal">
        <div class="modal-content">
            <h3 style="color:#fff">⚙️ 配置节点参数</h3>
            <form id="configForm">
                <input type="hidden" id="target_ip" name="target_ip">
                <label>节点备注</label><input type="text" name="remark" value="V40_NODE">
                <label>端口</label><input type="number" name="port" value="12345">
                <label>协议</label>
                <select name="protocol">
                    <option value="vless">VLESS (Reality)</option>
                    <option value="vmess">VMess</option>
                    <option value="trojan">Trojan</option>
                </select>
                <label>UUID / Password</label><input type="text" name="uuid" id="uuid">
                <button type="button" class="btn" style="width:100%; margin-top:15px" onclick="submitSync()">🚀 立即推送到小鸡</button>
                <button type="button" class="btn" style="width:100%; margin-top:10px; background:#2a2d3e" onclick="closeEdit()">取消</button>
            </form>
        </div>
    </div>

    <script>
        function openEdit(ip) {
            document.getElementById('target_ip').value = ip;
            document.getElementById('uuid').value = '{{ uuid }}';
            document.getElementById('editModal').style.display = 'block';
        }
        function closeEdit() { document.getElementById('editModal').style.display = 'none'; }
        async function submitSync() {
            const formData = new FormData(document.getElementById('configForm'));
            const data = Object.fromEntries(formData.entries());
            const resp = await fetch('/send_v2', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(data)
            });
            const res = await resp.json();
            alert(res.msg);
            closeEdit();
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
    return '<h2>MultiX Login</h2><form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form>'

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/login')

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, master=get_master_stats(), agents_count=len(AGENTS), agents=AGENTS, uuid=secrets.token_hex(16))

@app.route('/send_v2', methods=['POST'])
def send_v2():
    if not session.get('logged'): return jsonify({"msg": "Unauthorized"}), 403
    req = request.json
    target_ip = req.get('target_ip')
    node_data = {
        "remark": f"MX-{req['remark']}", "port": int(req['port']), "protocol": req['protocol'],
        "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}], "decryption": "none"}),
        "stream_settings": json.dumps({
            "network": "tcp", "security": "reality",
            "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "YOUR_PRIVATE_KEY", "shortIds": ["abcdef123456"]}
        }),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if target_ip in AGENTS:
        LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[target_ip]['ws'].send(payload))
        return jsonify({"msg": f"已成功推送到 {target_ip}"})
    return jsonify({"msg": "节点不在线"}), 404

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth_msg).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'heartbeat': AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

async def start_ws():
    global LOOP
    LOOP = asyncio.get_running_loop()
    async with websockets.serve(ws_server, "::", 8888): await asyncio.Future()

if __name__ == '__main__':
    Thread(target=lambda: asyncio.run(start_ws()), daemon=True).start()
    app.run(host='0.0.0.0', port=$M_PORT)
EOF
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    IPV4=$(curl -s4 https://api64.ipify.org || echo "None")
    echo -e "${G}==========================================${NC}"
    echo -e "🎉 MultiX V4.0 主控部署成功！"
    echo -e "🔗 面板地址: http://${IPV4}:${M_PORT}"
    echo -e "👤 账号密码: ${M_USER} / ${M_PASS}"
    echo -e "🔑 鉴权 Token: ${Y}${M_TOKEN}${NC}"
    echo -e "${G}==========================================${NC}"
    read -p "按回车返回菜单"
}

# --- 被控端安装 (保持逻辑一致) ---
install_agent() {
    echo -e "${G}--- 被控端安装 (V4.0 自愈版) ---${NC}"
    read -p "请输入主控 Token: " A_TOKEN
    read -p "自定义面板端口 [默认 2053]: " P_WEB
    P_WEB=${P_WEB:-2053}
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    fuser -k ${P_WEB}/tcp 2096/tcp 2>/dev/null
    apt update && apt install -y sqlite3 docker.io psmisc lsof
    mkdir -p ${INSTALL_PATH}/agent/db_data
    docker rm -f 3x-ui multix-agent 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host \
      -e XUI_PORT=${P_WEB} \
      -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${MASTER_DOMAIN}:8888"
TOKEN = "$A_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"
def get_db_columns():
    conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(inbounds)"); cols = [i[1] for i in cursor.fetchall()]
    conn.close(); return cols
async def handle_task(data):
    try:
        client = docker.from_env(); xui = client.containers.get("3x-ui")
        cols = get_db_columns(); xui.stop(); time.sleep(2)
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        mapping = {"remark": data['remark'], "port": int(data['port']), "protocol": data['protocol'], "settings": data['settings'], "stream_settings": data['stream_settings'], "sniffing": data['sniffing'], "enable": 1, "tag": f"inbound-{data['port']}", "up": 0, "down": 0, "total": 0, "expiry_time": 0, "user_id": 1}
        final_fields = [f for f in cols if f in mapping or f == "id"]
        placeholders = ",".join(["?" if f != "id" else "NULL" for f in final_fields])
        cursor.execute(f"INSERT OR REPLACE INTO inbounds ({','.join(final_fields)}) VALUES ({placeholders})", [mapping[f] for f in final_fields if f != "id"])
        conn.commit(); conn.close(); xui.start()
    except Exception as e: print(f"Error: {e}")
async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    task = json.loads(msg)
                    if task.get('token') == TOKEN: await handle_task(task['data'])
        except: await asyncio.sleep(5)
if __name__ == '__main__': asyncio.run(run_agent())
EOF
    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil docker -i https://pypi.tuna.tsinghua.edu.cn/simple
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image
    echo -e "${G}✅ 被控端部署完成！${NC}"
}

while true; do show_menu; case $choice in 1) install_master ;; 3) install_agent ;; 7) smart_repair ;; 5) exit 0 ;; esac; done
