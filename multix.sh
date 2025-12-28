#!/bin/bash
# MultiX V4.5 - 极客透明版 (快捷命令 + 状态管理 + 档案查看)

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V4.5        "
    echo -e "    快捷命令: multix | 状态自愈     "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看本机配置信息 (管理凭据)"
    echo "4. 📊 查看服务运行状态"
    echo "5. ⚡ 启动/停止/重启服务"
    echo "----------------------------------"
    echo "7. 🔧 智能一键修复 (解决端口占用)"
    echo "9. 🗑️  完全卸载 (慎用)"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [0-9]: " choice
}

# --- 功能：查看配置档案 ---
show_config() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      🛰️ MultiX 本机配置档案       "
    echo -e "${G}==================================${NC}"
    
    # 探测主控配置
    if [ -f "$INSTALL_PATH/master/app.py" ]; then
        M_PORT=$(grep "port=" "$INSTALL_PATH/master/app.py" | tail -1 | sed -E 's/.*port=([0-9]+).*/\1/')
        M_USER=$(grep -P 'request.form\["u"\] ==' "$INSTALL_PATH/master/app.py" | cut -d'"' -f2)
        M_PASS=$(grep -P 'request.form\["p"\] ==' "$INSTALL_PATH/master/app.py" | cut -d'"' -f4)
        M_TOKEN=$(grep "AUTH_TOKEN =" "$INSTALL_PATH/master/app.py" | head -1 | cut -d'"' -f2)
        echo -e "${Y}[ 主控端 (Master) ]${NC}"
        echo -e " - 面板地址: ${G}http://$(curl -s4 https://api64.ipify.org):${M_PORT:-7575}${NC}"
        echo -e " - 管理账号: ${G}${M_USER:-admin}${NC}"
        echo -e " - 管理密码: ${G}${M_PASS:-admin}${NC}"
        echo -e " - 通信 Token: ${Y}${M_TOKEN}${NC}"
    else
        echo -e "${R}[ 主控端 ] : 未安装 (或非主控机器)${NC}"
    fi

    echo -e "----------------------------------"

    # 探测被控配置
    if [ -f "$INSTALL_PATH/agent/agent.py" ]; then
        A_MASTER=$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
        A_TOKEN=$(grep "TOKEN =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
        echo -e "${Y}[ 被控端 (Agent) ]${NC}"
        echo -e " - 连接主控: ${G}$A_MASTER${NC}"
        echo -e " - 本机 Token: ${Y}$A_TOKEN${NC}"
        X_PORT=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' 3x-ui 2>/dev/null)
        echo -e " - 3x-ui 端口: ${G}${X_PORT:-"Host模式"}${NC}"
    else
        echo -e "${R}[ 被控端 ] : 未安装 (或非被控小鸡)${NC}"
    fi
    echo -e "${G}==================================${NC}"
    read -p "按回车返回菜单..."
}

# --- 功能：状态查询 ---
show_status() {
    echo -e "\n${Y}[*] 正在检索服务状态...${NC}"
    # 主控进程
    M_PID=$(pgrep -f "master/app.py")
    if [ ! -z "$M_PID" ]; then echo -e "主控进程: ${G}● Running (PID: $M_PID)${NC}"; else echo -e "主控进程: ${R}○ Stopped${NC}"; fi
    # Docker 容器
    if command -v docker &>/dev/null; then
        containers=("3x-ui" "multix-agent")
        for c in "${containers[@]}"; do
            if [ "$(docker ps -q -f name=$c)" ]; then echo -e "$c 容器: ${G}● Running${NC}"; else echo -e "$c 容器: ${R}○ Stopped${NC}"; fi
        done
    fi
    read -p "按回车返回..."
}

# --- 功能：服务管理 ---
manage_service() {
    echo -e "\n1. ${G}启动${NC}所有服务 | 2. ${R}停止${NC}所有服务 | 3. ${Y}重启${NC}所有服务"
    read -p "选择操作: " op
    case $op in
        1)
            [ -f "$INSTALL_PATH/master/app.py" ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
            docker start 3x-ui multix-agent 2>/dev/null
            echo "服务已尝试启动";;
        2)
            pkill -f "master/app.py" 2>/dev/null
            docker stop 3x-ui multix-agent 2>/dev/null
            echo "服务已停止";;
        3)
            pkill -f "master/app.py" 2>/dev/null
            [ -f "$INSTALL_PATH/master/app.py" ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
            docker restart 3x-ui multix-agent 2>/dev/null
            echo "服务已重启";;
    esac
    sleep 1
}

# --- 智能修复逻辑 (保留原有逻辑) ---
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

# --- 安装主控端 (保留 Dashboard 4.0 逻辑) ---
install_master() {
    echo -e "${G}[+] 启动 V4.5 主控安装向导...${NC}"
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
    apt update && apt install -y python3 python3-pip psmisc curl lsof sqlite3
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
    <title>MultiX V4.5 Dashboard</title>
    <style>
        body { background: #0f111a; color: #a6adbb; font-family: 'Segoe UI', sans-serif; margin: 0; display: flex; }
        .sidebar { width: 240px; background: #1a1c27; height: 100vh; padding: 20px; border-right: 1px solid #2a2d3e; }
        .main { flex: 1; padding: 30px; overflow-y: auto; }
        .card { background: #1a1c27; border-radius: 12px; padding: 20px; margin-bottom: 20px; border: 1px solid #2a2d3e; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 20px; }
        .stat-val { font-size: 24px; color: #fff; font-weight: bold; }
        .stat-label { font-size: 12px; color: #646b7b; text-transform: uppercase; }
        .btn { background: #5865f2; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; transition: 0.3s; }
        .badge { background: #232733; padding: 4px 10px; border-radius: 4px; font-size: 12px; color: #00ff00; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 100; }
        .modal-content { background: #1a1c27; margin: 5% auto; padding: 30px; width: 450px; border-radius: 15px; border: 1px solid #2a2d3e; }
        input, select { background: #0f111a; border: 1px solid #2a2d3e; color: #fff; padding: 8px; width: 100%; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="sidebar">
        <h2 style="color:#fff">🛰️ MultiX V4.5</h2>
        <div style="cursor:pointer; padding:10px 0; color:#fff">📊 运行概览</div>
        <div style="margin-top:50px"><a href="/logout" style="color:#ff4d4d; text-decoration:none">🚪 退出登录</a></div>
    </div>
    <div class="main">
        <h3>📊 主控机系统状态</h3>
        <div class="grid">
            <div class="card"><div class="stat-label">CPU</div><div class="stat-val">{{ master.cpu }}%</div></div>
            <div class="card"><div class="stat-label">MEM</div><div class="stat-val">{{ master.mem }}%</div></div>
            <div class="card"><div class="stat-label">DISK</div><div class="stat-val">{{ master.disk }}%</div></div>
            <div class="card"><div class="stat-label">UPTIME</div><div class="stat-val">{{ master.uptime }}h</div></div>
        </div>
        <h3>📡 节点管理 (在线: {{ agents_count }})</h3>
        <div class="grid">
            {% for ip, info in agents.items() %}
            <div class="card">
                <div style="display:flex; justify-content:space-between"><span>{{ ip }}</span><span class="badge">Online</span></div>
                <button class="btn" style="margin-top:10px" onclick="openEdit('{{ ip }}')">配置节点</button>
            </div>
            {% endfor %}
        </div>
    </div>
    <div id="editModal" class="modal">
        <div class="modal-content">
            <h3>⚙️ 配置节点参数</h3>
            <form id="configForm">
                <input type="hidden" id="target_ip" name="target_ip">
                <input type="text" name="remark" value="V45_STABLE">
                <input type="number" name="port" value="12345">
                <select name="protocol"><option value="vless">VLESS</option></select>
                <input type="text" name="uuid" id="uuid">
                <button type="button" class="btn" onclick="submitSync()">🚀 立即推送</button>
                <button type="button" class="btn" style="background:#2a2d3e" onclick="closeEdit()">取消</button>
            </form>
        </div>
    </div>
    <script>
        function openEdit(ip) { document.getElementById('target_ip').value = ip; document.getElementById('uuid').value = '{{ uuid }}'; document.getElementById('editModal').style.display = 'block'; }
        function closeEdit() { document.getElementById('editModal').style.display = 'none'; }
        async function submitSync() {
            const formData = new FormData(document.getElementById('configForm'));
            const data = Object.fromEntries(formData.entries());
            const resp = await fetch('/send_v2', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
            const res = await resp.json(); alert(res.msg); closeEdit();
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
def logout(): session.clear(); return redirect('/login')

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
        "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "YOUR_KEY", "shortIds": ["abcdef123456"]}}),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if target_ip in AGENTS:
        LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[target_ip]['ws'].send(payload))
        return jsonify({"msg": f"已推送至 {target_ip}"})
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
    
    # 注入快捷命令
    install_shortcut
    
    echo -e "${G}==========================================${NC}"
    echo -e "🎉 MultiX V4.5 主控部署成功！"
    echo -e "🔗 面板地址: http://$(curl -s4 https://api64.ipify.org):$M_PORT"
    echo -e "🔑 鉴权 Token: ${Y}${M_TOKEN}${NC}"
    echo -e "⌨️  快捷命令: ${G}multix${NC}"
    echo -e "${G}==========================================${NC}"
    read -p "按回车返回菜单"
}

# --- 安装被控端 (保留 V4.0 逻辑) ---
install_agent() {
    echo -e "${G}--- 被控端安装 (V4.5 极客版) ---${NC}"
    read -p "请输入主控端通信 Token: " A_TOKEN
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
    
    install_shortcut
    echo -e "${G}✅ 被控端部署完成！⌨️  快捷命令: multix${NC}"
    read -p "按回车返回..."
}

# --- 快捷命令安装函数 ---
install_shortcut() {
    # 将当前运行的脚本复制到系统路径
    cat > /usr/local/bin/multix <<EOF
#!/bin/bash
bash <(cat <<'INNEREOF'
$(cat "$0")
INNEREOF
)
EOF
    chmod +x /usr/local/bin/multix
}

# --- 执行主流程 ---
while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) show_config ;;
        4) show_status ;;
        5) manage_service ;;
        7) smart_repair ;;
        9) 
            read -p "确认卸载？(y/n): " confirm
            if [ "$confirm" == "y" ]; then
                pkill -f "master/app.py"
                docker rm -f 3x-ui multix-agent 2>/dev/null
                rm -rf $INSTALL_PATH /usr/local/bin/multix
                echo "已完全卸载。"
                exit 0
            fi ;;
        0) exit 0 ;;
        *) echo "无效选项" ; sleep 1 ;;
    esac
done
