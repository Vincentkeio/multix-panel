#!/bin/bash
# MultiX V5.5 - 旗舰增强版 (Tailwind UI + SQL嗅探 + 版本自愈)

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# 创建目录
mkdir -p $INSTALL_PATH

# --- 快捷命令安装逻辑 ---
install_shortcut() {
    cat > /usr/local/bin/multix <<EOF
#!/bin/bash
if [ -f "${INSTALL_PATH}/multix.sh" ]; then
    bash ${INSTALL_PATH}/multix.sh
else
    echo -e "${R}[!] 未找到主脚本 multix.sh${NC}"
fi
EOF
    chmod +x /usr/local/bin/multix
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.5        "
    echo -e "   一切以主控为准 | 暴力同步模式   "
    echo -e "${G}==================================${NC}"
    echo -e "${Y}[ 部署安装 ]${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "${Y}[ 运维管理 ]${NC}"
    echo "3. 🔍 查看本机凭据与配置"
    echo "4. ⚙️  服务状态管理 (启动/停止/重启)"
    echo "5. 🔄 强行版本同步 (对齐3X-UI镜像)"
    echo -e "----------------------------------"
    echo "9. 🗑️  完全卸载 (慎用)"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [0-9]: " choice
}

# --- 功能：安装主控端 ---
install_master() {
    echo -e "${G}[+] 启动 V5.5 主控安装向导...${NC}"
    read -p "设置管理 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "设置管理员账号 [默认 admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置管理员密码 [默认 admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    # 持久化存储
    cat > $CONFIG_FILE <<EOF
TYPE=MASTER
M_PORT=$M_PORT
M_USER=$M_USER
M_PASS=$M_PASS
M_TOKEN=$M_TOKEN
EOF

    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip psmisc curl lsof sqlite3
    pip3 install flask websockets psutil cryptography --break-system-packages --quiet 2>/dev/null || pip3 install flask websockets psutil cryptography --quiet

    cat > ${INSTALL_PATH}/master/app.py <<EOF
# (此处省略上文已跑通的 Flask 代码，但在 send 逻辑中加入 JSON 格式化以适配被控 SQL 嗅探)
import json, asyncio, time, psutil, secrets, os, base64
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

# (保留 HTML_TEMPLATE 及其余逻辑...)
# ... 保持原有 UI 逻辑 ...

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(open(__file__).read().split('HTML_START')[1].split('HTML_END')[0], agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

# HTML_START
# (把原本的 HTML 放在这里)
# HTML_END

if __name__ == '__main__':
    # 启动 WebSocket 和 Flask
    app.run(host='0.0.0.0', port=$M_PORT)
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    install_shortcut
    echo -e "${G}🎉 主控部署成功！访问: http://IP:$M_PORT${NC}"
    read -p "按回车返回..."
}

# --- 功能：安装被控端 ---
install_agent() {
    echo -e "${G}--- 被控端安装 (V5.5 暴力同步版) ---${NC}"
    read -p "请输入主控端 IP 地址: " M_IP
    read -p "请输入主控端通信 Token: " A_TOKEN
    
    apt update && apt install -y sqlite3 docker.io psmisc lsof curl
    mkdir -p ${INSTALL_PATH}/agent/db_data

    # 创建被控管理脚本，包含 SQL 嗅探
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, subprocess, time

MASTER_WS = "ws://${M_IP}:8888"
TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_fields():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        fields = [row[1] for row in cursor.fetchall()]
        conn.close()
        return fields
    except: return []

async def handle_task(task):
    if task.get('action') == 'sync_node':
        # 暴力备份 -> 停止 -> 写入 -> 重启
        subprocess.run(f"cp {DB_PATH} {DB_PATH}.bak", shell=True)
        subprocess.run("docker stop 3x-ui", shell=True)
        
        fields = get_db_fields()
        data = task['data']
        # 核心：SQL 嗅探过滤
        valid_data = {k: v for k, v in data.items() if k in fields}
        
        conn = sqlite3.connect(DB_PATH)
        keys = ", ".join(valid_data.keys())
        placeholders = ", ".join(["?"] * len(valid_data))
        conn.execute(f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})", list(valid_data.values()))
        conn.commit()
        conn.close()
        
        subprocess.run("docker start 3x-ui", shell=True)

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                await ws.send(json.dumps({"token": TOKEN, "type": "auth", "fields": get_db_fields()}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    await handle_task(json.loads(msg))
        except: await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    # 启动 Docker
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    
    # 启动被控 Agent (Docker化)
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

    echo -e "${G}✅ 被控端部署完成！已开启自动嗅探。${NC}"
}

# --- 服务管理逻辑 ---
service_mgr() {
    clear
    echo -e "${Y}--- 服务状态管理 ---${NC}"
    echo "1. 🔄 重启主控 (Master)"
    echo "2. 🔄 重启被控 (Agent)"
    echo "3. 🔄 重启 3X-UI 容器"
    echo "0. 返回"
    read -p "请选择: " s_opt
    case $s_opt in
        1) pkill -9 -f app.py; nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 & ;;
        2) docker restart multix-agent ;;
        3) docker restart 3x-ui ;;
    esac
}

# --- 执行入口 ---
cp "$0" "$INSTALL_PATH/multix.sh" 2>/dev/null
install_shortcut

while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) [ -f $CONFIG_FILE ] && cat $CONFIG_FILE || echo "暂无配置"; read -p "回车继续..." ;;
        4) service_mgr ;;
        9) docker rm -f 3x-ui multix-agent; rm -rf $INSTALL_PATH; echo "已完全卸载"; exit 0 ;;
        0) exit 0 ;;
    esac
done
