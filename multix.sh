#!/bin/bash
# MultiX MVP V3.7 - 动态字段适配版 (AI-Driven SQL)
# 核心特性：自动探测 3x-ui 数据库结构，解决版本更新崩溃问题

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"

# 颜色定义
G='\033[0;32m'
R='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V3.7        "
    echo -e "    自动探测 & 动态适配数据库      "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 🗑️  卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 📡 安装/重装 被控端 (Agent + 3x-ui)"
    echo "4. 🗑️  卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "6. 🆘 一键救砖/深度清理 (清理残留、修复崩溃)"
    echo "----------------------------------"
    echo "5. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [1-6]: " choice
}

deep_fix() {
    echo -e "${R}[!] 正在执行深度清理程序...${NC}"
    for port in 2053 2096 7575 8888; do fuser -k ${port}/tcp 2>/dev/null; done
    docker rm -f multix-agent 3x-ui 2>/dev/null
    docker rmi multix-agent-image 2>/dev/null
    if [ -f "${INSTALL_PATH}/agent/db_data/x-ui.db" ]; then
        sqlite3 "${INSTALL_PATH}/agent/db_data/x-ui.db" "DELETE FROM inbounds WHERE remark LIKE 'MX-%';"
    fi
    mkdir -p ${INSTALL_PATH}/agent/db_data
    docker run -d --name 3x-ui --restart always --network host \
      -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    echo -e "${G}✅ 深度清理完成！${NC}"
    sleep 2
}

install_master() {
    echo -e "${G}[+] 正在部署主控端...${NC}"
    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip net-tools psmisc
    pip3 install flask websockets psutil --break-system-packages --quiet || pip3 install flask websockets psutil --quiet

    cat > ${INSTALL_PATH}/master/app.py <<'EOF'
import json, asyncio, time, psutil, secrets, os
from flask import Flask, render_template_string, request
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)
AGENTS = {} 
LOOP = None

def generate_xui_sql(remark, port, protocol, uuid):
    sniffing = {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    settings = {"clients": [{"id": uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"}
    stream_settings = {"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "YOUR_KEY", "shortIds": ["abcdef123456"]}}
    return {"remark": f"MX-{remark}", "port": int(port), "protocol": protocol, "settings": json.dumps(settings), "stream_settings": json.dumps(stream_settings), "sniffing": json.dumps(sniffing)}

HTML = """
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>MultiX V3.7</title>
<style>body{background:#1a1a1a;color:white;padding:20px} .card{background:#252525;padding:15px;border-radius:8px;margin-bottom:20px;border:1px solid #444} input{background:#333;color:white;border:1px solid #555;padding:8px;margin:5px;border-radius:4px} .btn{background:#177ddc;color:white;border:none;padding:10px 20px;border-radius:4px;cursor:pointer}</style></head>
<body>
    <h2>🛰️ MultiX V3.7 控制台</h2>
    <div class="card"><h3>在线节点: {{ agents_count }}</h3>
    {% for ip, info in agents.items() %}
    <div style="padding:5px;border-bottom:1px solid #333">🌐 {{ ip }} | CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}%</div>
    {% endfor %}</div>
    <div class="card"><form action="/send" method="post">
    备注: <input name="remark" value="V37_Auto"> 端口: <input name="port" value="12345"> UUID: <input name="uuid" value="{{ default_uuid }}" style="width:300px"><br><br>
    <button type="submit" class="btn">🚀 动态全集群同步</button></form></div>
</body></html>
"""

@app.route('/')
def index(): return render_template_string(HTML, agents_count=len(AGENTS), agents=AGENTS, default_uuid=secrets.token_hex(16))

@app.route('/send', methods=['POST'])
def send_cmd():
    try:
        node_data = generate_xui_sql(request.form['remark'], request.form['port'], "vless", request.form['uuid'])
        payload = json.dumps({"action": "sync_node", "data": node_data})
        if LOOP:
            for ip in list(AGENTS.keys()): LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[ip]['ws'].send(payload))
            return "✅ 指令已送达！<a href='/'>返回</a>"
    except Exception as e: return f"错误：{e}"

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
    try:
        async for msg in websocket:
            data = json.loads(msg); 
            if data.get('type') == 'heartbeat': AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

async def start_ws():
    global LOOP
    LOOP = asyncio.get_running_loop()
    async with websockets.serve(ws_server, "::", 8888): await asyncio.Future()

if __name__ == '__main__':
    Thread(target=lambda: asyncio.run(start_ws()), daemon=True).start()
    app.run(host='0.0.0.0', port=7575)
EOF
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    echo -e "${G}✅ 主控已启动。${NC}"
    read -p "按回车键返回菜单"
}

install_agent() {
    echo -e "${G}[+] 正在环境自愈与被控部署...${NC}"
    apt install -y psmisc sqlite3 docker.io
    deep_fix

    # 构建动态适配镜像
    cat > ${INSTALL_PATH}/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil docker -i https://pypi.tuna.tsinghua.edu.cn/simple
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF

    # 核心：动态探测字段的 Agent 逻辑
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${MASTER_DOMAIN}:8888"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_columns():
    """动态获取 inbounds 表的所有列名"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(inbounds)")
    columns = [info[1] for info in cursor.fetchall()]
    conn.close()
    return columns

async def handle_task(data):
    try:
        client = docker.from_env()
        xui = client.containers.get("3x-ui")
        cols = get_db_columns()
        print(f"[*] 探测到数据库列: {cols}")
        
        xui.stop()
        time.sleep(2)
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # 核心：根据探测到的列名动态构造 SQL
        mapping = {
            "remark": data['remark'],
            "port": int(data['port']),
            "protocol": data['protocol'],
            "settings": data['settings'],
            "stream_settings": data['stream_settings'],
            "sniffing": data['sniffing'],
            "enable": 1,
            "tag": f"inbound-{data['port']}",
            "listen": "",
            "up": 0, "down": 0, "total": 0, "expiry_time": 0,
            "all_time": 0, "traffic_reset": "never", "last_traffic_reset_time": 0, "user_id": 1
        }
        
        # 只取数据库中存在的字段
        final_fields = [f for f in cols if f in mapping or f == "id"]
        placeholders = ",".join(["?" if f != "id" else "NULL" for f in final_fields])
        field_names = ",".join(final_fields)
        
        values = [mapping[f] for f in final_fields if f != "id"]
        
        sql = f"INSERT OR REPLACE INTO inbounds ({field_names}) VALUES ({placeholders})"
        cursor.execute(sql, values)
        
        conn.commit()
        conn.close()
        xui.start()
        print(f"[+] 动态写库成功！已适配 {len(final_fields)} 个字段")
    except Exception as e: print(f"[!] 错误: {e}")

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS, ping_interval=20) as ws:
                print("[+] 动态隧道已就绪")
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node': await handle_task(task['data'])
        except Exception as e:
            await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    cd ${INSTALL_PATH}/agent && docker build -t multix-agent-image .
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${INSTALL_PATH}/agent:/app -v ${INSTALL_PATH}/agent/db_data:/app/db_share \
      multix-agent-image
    echo -e "${G}✅ 动态适配版 Agent 部署完成！${NC}"
    read -p "按回车键返回菜单"
}

uninstall_master() { pkill -9 -f app.py && rm -rf ${INSTALL_PATH}/master; echo "已卸载"; }
uninstall_agent() { docker rm -f multix-agent 3x-ui && docker rmi multix-agent-image; echo "已卸载"; }

while true; do show_menu; case $choice in 1) install_master ;; 2) uninstall_master ;; 3) install_agent ;; 4) uninstall_agent ;; 6) deep_fix ;; 5) exit 0 ;; esac; done
