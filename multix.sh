#!/bin/bash

# ==============================================================================
# MultiX Cluster Installer - v7.0
# ==============================================================================
# 允许调用外部 CDN 资源构建高颜值 Web UI
# 严格的冲突检测与环境清理机制
# ==============================================================================

# --- [ 全局配置 ] ---
INSTALL_PATH="/opt/multix"
DB_PATH="${INSTALL_PATH}/db"
LOG_PATH="${INSTALL_PATH}/logs"
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053

# --- [ 语言包 ] ---
# 默认中文，可通过菜单切换
CURRENT_LANG="zh"

# 文本字典 (模拟 i18n)
declare -A MSG_ZH
declare -A MSG_EN

MSG_ZH[welcome]="欢迎使用 MultiX 集群部署工具"
MSG_ZH[check_root]="错误: 请使用 root 权限运行"
MSG_ZH[check_docker]="正在检查 Docker 环境..."
MSG_ZH[conflict_detect]="正在检测端口和容器冲突..."
MSG_ZH[conflict_found]="警告: 检测到可能冲突的 3x-ui 容器或端口占用！"
MSG_ZH[clean_ask]="检测到冲突，是否执行深度清理 (卸载旧版 3x-ui)？(y/n)"
MSG_ZH[clean_done]="环境清理完毕。"
MSG_ZH[clean_abort]="操作已取消，安装终止。"
MSG_ZH[install_master]="正在构建 Master 主控端 (Vue3 + Element Plus UI)..."
MSG_ZH[install_agent]="正在构建 Agent 被控端 (集成 3x-ui)..."
MSG_ZH[success]="安装成功！"
MSG_ZH[uninstall_ask]="危险: 确定要卸载 MultiX 及其所有数据吗？(y/n)"

MSG_EN[welcome]="Welcome to MultiX Cluster Installer"
MSG_EN[check_root]="Error: Root privileges required"
MSG_EN[check_docker]="Checking Docker environment..."
MSG_EN[conflict_detect]="Scanning for conflicts..."
MSG_EN[conflict_found]="WARNING: Conflict detected (Existing 3x-ui or Port usage)!"
MSG_EN[clean_ask]="Conflict found. Perform deep clean (Uninstall old 3x-ui)? (y/n)"
MSG_EN[clean_done]="Environment cleaned."
MSG_EN[clean_abort]="Aborted by user."
MSG_EN[install_master]="Building Master Dashboard (Vue3 + Element Plus UI)..."
MSG_EN[install_agent]="Building Agent (Integrated 3x-ui)..."
MSG_EN[success]="Installation Successful!"
MSG_EN[uninstall_ask]="DANGER: Uninstall MultiX and ALL data? (y/n)"

# --- [ 工具函数 ] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

msg() {
    key=$1
    if [ "$CURRENT_LANG" == "zh" ]; then echo -e "${MSG_ZH[$key]}"; else echo -e "${MSG_EN[$key]}"; fi
}

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}$(msg check_root)${PLAIN}" && exit 1
}

set_language() {
    echo -e "Select Language / 选择语言:"
    echo -e "1. 简体中文 (Chinese)"
    echo -e "2. English"
    read -p "Input: " l
    if [ "$l" == "2" ]; then CURRENT_LANG="en"; else CURRENT_LANG="zh"; fi
    # 保存语言偏好 (简单实现)
    mkdir -p $INSTALL_PATH
    echo "$CURRENT_LANG" > $INSTALL_PATH/.lang
}

load_language() {
    if [ -f "$INSTALL_PATH/.lang" ]; then
        CURRENT_LANG=$(cat $INSTALL_PATH/.lang)
    fi
}

# --- [ 核心：冲突检测与清理 ] ---
check_conflict() {
    echo -e "${YELLOW}$(msg conflict_detect)${PLAIN}"
    CONFLICT=0
    
    # 1. 检查 2053 端口
    if netstat -tlpn | grep -q ":${DEFAULT_XUI_PORT} "; then CONFLICT=1; fi
    # 2. 检查常见容器名
    if docker ps -a --format '{{.Names}}' | grep -Eq "^3x-ui$|^x-ui$"; then CONFLICT=1; fi

    if [ $CONFLICT -eq 1 ]; then
        echo -e "${RED}$(msg conflict_found)${PLAIN}"
        echo -e "${RED}$(msg clean_ask)${PLAIN}"
        read -p "Input: " choice
        if [[ "$choice" == "y" ]]; then
            echo -e "${YELLOW}Cleaning up...${PLAIN}"
            docker rm -f 3x-ui x-ui multix-agent multix-master 2>/dev/null
            # 可选：清理旧数据，为了安全起见这里只停容器
            echo -e "${GREEN}$(msg clean_done)${PLAIN}"
        else
            echo -e "${RED}$(msg clean_abort)${PLAIN}"
            exit 1
        fi
    else
        echo -e "${GREEN}Environment is clean.${PLAIN}"
    fi
}

# --- [ Master 安装逻辑 ] ---
install_master() {
    echo -e "${GREEN}$(msg install_master)${PLAIN}"
    mkdir -p ${INSTALL_PATH}/master
    cd ${INSTALL_PATH}/master

    read -p "Set Master Port [Default ${DEFAULT_MASTER_PORT}]: " PORT
    PORT=${PORT:-$DEFAULT_MASTER_PORT}
    
    read -p "Set Admin Token: " TOKEN
    [ -z "$TOKEN" ] && TOKEN="admin123"

    # 生成 Python Flask 主控 (内嵌 Vue3 高颜值前端)
    # 这里使用了外部 CDN：Element Plus (Dark Theme)
    cat > app.py <<EOF
import os, json, time
from flask import Flask, request, jsonify, render_template_string
from threading import Lock

app = Flask(__name__)
TOKEN = "${TOKEN}"
AGENTS = {}
LOCK = Lock()

# --- Vue3 + Element Plus Single File Component ---
HTML = """
<!DOCTYPE html>
<html class="dark">
<head>
    <title>MultiX Cluster</title>
    <meta charset="utf-8">
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <link rel="stylesheet" href="https://unpkg.com/element-plus/dist/index.css" />
    <link rel="stylesheet" href="https://unpkg.com/element-plus/theme-chalk/dark/css-vars.css">
    <script src="https://unpkg.com/element-plus"></script>
    <script src="https://unpkg.com/@element-plus/icons-vue"></script>
    <style>
        body { margin: 0; background: #141414; color: #E5EAF3; font-family: 'Helvetica Neue', sans-serif; }
        .el-header { background: #1d1e1f; border-bottom: 1px solid #363637; display: flex; align-items: center; justify-content: space-between; }
        .status-dot { height: 8px; width: 8px; border-radius: 50%; display: inline-block; margin-right: 5px; }
        .online { background: #67C23A; box-shadow: 0 0 5px #67C23A; }
        .offline { background: #F56C6C; }
        .stat-card { background: #1d1e1f; border: 1px solid #363637; margin-bottom: 20px; }
        .stat-value { font-size: 24px; font-weight: bold; color: #409EFF; }
    </style>
</head>
<body>
    <div id="app">
        <el-container style="height: 100vh;">
            <el-header>
                <div style="font-size: 18px; font-weight: bold;"><el-icon style="vertical-align: middle; margin-right: 5px;"><Connection /></el-icon> MultiX Manager</div>
                <el-tag type="info">Port: ${PORT}</el-tag>
            </el-header>
            <el-main>
                <el-row :gutter="20">
                    <el-col :span="24" style="margin-bottom: 20px;">
                        <el-alert title="Cluster Running" type="success" :closable="false" show-icon>
                            Total Agents: {{ Object.keys(agents).length }}
                        </el-alert>
                    </el-col>
                </el-row>

                <el-row :gutter="20">
                    <el-col :span="6" v-for="(agent, ip) in agents" :key="ip">
                        <el-card class="stat-card" shadow="hover">
                            <template #header>
                                <div class="card-header" style="display: flex; justify-content: space-between; align-items: center;">
                                    <span>
                                        <span class="status-dot" :class="agent.status"></span>
                                        {{ agent.name }}
                                    </span>
                                    <el-tag size="small" effect="dark">{{ ip }}</el-tag>
                                </div>
                            </template>
                            <div style="display: flex; justify-content: space-between; text-align: center; margin-bottom: 15px;">
                                <div><div style="font-size: 12px; color: #909399;">CPU</div><div style="color: #E6A23C;">{{ agent.cpu }}%</div></div>
                                <div><div style="font-size: 12px; color: #909399;">RAM</div><div style="color: #409EFF;">{{ agent.mem }}%</div></div>
                                <div><div style="font-size: 12px; color: #909399;">Disk</div><div style="color: #F56C6C;">{{ agent.disk }}%</div></div>
                            </div>
                            <el-button-group style="width: 100%; display: flex;">
                                <el-button type="primary" plain style="flex: 1;" @click="openXui(ip, agent.xport)">面板 (X-UI)</el-button>
                                <el-button type="warning" plain style="flex: 1;" @click="configAgent(ip)">配置</el-button>
                            </el-button-group>
                        </el-card>
                    </el-col>
                </el-row>
            </el-main>
        </el-container>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        const app = createApp({
            setup() {
                const agents = ref({});
                const fetchAgents = async () => {
                    try {
                        const res = await fetch('/api/agents');
                        agents.value = await res.json();
                    } catch(e) {}
                };
                const openXui = (ip, port) => window.open(\`http://\${ip}:\${port}\`, '_blank');
                const configAgent = (ip) => alert('Config feature coming in next step!');
                
                onMounted(() => {
                    setInterval(fetchAgents, 3000);
                    fetchAgents();
                });
                return { agents, openXui, configAgent };
            }
        });
        app.use(ElementPlus);
        for (const [key, component] of Object.entries(ElementPlusIconsVue)) { app.component(key, component) }
        app.mount("#app");
    </script>
</body>
</html>
"""

@app.route('/')
def index(): return render_template_string(HTML)

@app.route('/api/heartbeat', methods=['POST'])
def heartbeat():
    if request.headers.get('Authorization') != TOKEN: return jsonify({'msg': '403'}), 403
    data = request.json
    ip = request.remote_addr
    with LOCK:
        AGENTS[ip] = {
            'name': data.get('name', 'Unknown'),
            'cpu': data.get('cpu', 0),
            'mem': data.get('mem', 0),
            'disk': data.get('disk', 0),
            'xport': data.get('xport', 2053),
            'status': 'online',
            'last_seen': time.time()
        }
    return jsonify({'status': 'ok'})

@app.route('/api/agents')
def get_agents():
    # 简单的离线检测逻辑
    now = time.time()
    with LOCK:
        for ip in AGENTS:
            if now - AGENTS[ip]['last_seen'] > 15: AGENTS[ip]['status'] = 'offline'
    return jsonify(AGENTS)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=${PORT})
EOF

    # Dockerfile
    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask requests" >> Dockerfile
    echo "COPY app.py /app.py" >> Dockerfile
    echo "CMD [\"python\", \"/app.py\"]" >> Dockerfile

    # Build & Run
    docker rm -f multix-master 2>/dev/null
    docker build -t multix-master .
    docker run -d --name multix-master --restart always --network host multix-master
    
    echo -e "${GREEN}$(msg success)${PLAIN}"
    echo -e "Master UI: http://YOUR_IP:${PORT}"
}

# --- [ Agent 安装逻辑 ] ---
install_agent() {
    # 1. 冲突检测
    check_conflict
    
    echo -e "${GREEN}$(msg install_agent)${PLAIN}"
    mkdir -p ${INSTALL_PATH}/agent
    cd ${INSTALL_PATH}/agent

    read -p "Master IP: " MASTER_IP
    read -p "Master Port [Default ${DEFAULT_MASTER_PORT}]: " MASTER_PORT
    MASTER_PORT=${MASTER_PORT:-$DEFAULT_MASTER_PORT}
    read -p "Token: " TOKEN
    [ -z "$TOKEN" ] && TOKEN="admin123"

    # Agent Python Script (上报状态 + 接收命令)
    cat > agent.py <<EOF
import time, requests, psutil, os, socket
from threading import Thread

MASTER_URL = "http://${MASTER_IP}:${MASTER_PORT}/api/heartbeat"
TOKEN = "${TOKEN}"
HOSTNAME = socket.gethostname()

def get_stats():
    return {
        'name': HOSTNAME,
        'cpu': int(psutil.cpu_percent(interval=1)),
        'mem': int(psutil.virtual_memory().percent),
        'disk': int(psutil.disk_usage('/').percent),
        'xport': int(os.getenv('XUI_PORT', 2053))
    }

def loop():
    while True:
        try:
            requests.post(MASTER_URL, json=get_stats(), headers={'Authorization': TOKEN}, timeout=5)
        except: pass
        time.sleep(5)

if __name__ == '__main__':
    print("Agent Started...")
    loop()
EOF

    # Dockerfile for Agent Sidecar
    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install requests psutil" >> Dockerfile
    echo "COPY agent.py /agent.py" >> Dockerfile
    echo "CMD [\"python\", \"/agent.py\"]" >> Dockerfile

    # Docker Compose (集成 3x-ui)
    cat > docker-compose.yml <<EOF
services:
  xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    network_mode: host
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
    restart: always
    environment:
      XUI_PORT: ${DEFAULT_XUI_PORT}
  
  multix-agent:
    build: .
    container_name: multix-agent
    network_mode: host
    restart: always
    environment:
      XUI_PORT: ${DEFAULT_XUI_PORT}
EOF

    echo -e "${YELLOW}Deploying containers...${PLAIN}"
    docker compose up -d --build
    echo -e "${GREEN}$(msg success)${PLAIN}"
}

# --- [ 卸载逻辑 ] ---
uninstall() {
    echo -e "${RED}$(msg uninstall_ask)${PLAIN}"
    read -p "Confirm (y/n): " c
    if [[ "$c" == "y" ]]; then
        docker rm -f multix-master multix-agent 3x-ui 2>/dev/null
        rm -rf ${INSTALL_PATH}
        echo -e "${GREEN}Uninstalled.${PLAIN}"
    else
        echo "Cancelled."
    fi
}

# --- [ 菜单界面 ] ---
show_menu() {
    load_language
    clear
    echo -e "==========================================="
    echo -e "   MultiX Cluster Installer ${YELLOW}[v7.0]${PLAIN}"
    echo -e "==========================================="
    echo -e "Current Lang: $CURRENT_LANG"
    echo -e "-------------------------------------------"
    echo -e " 1. Install Master (Web Panel :7575)"
    echo -e " 2. Install Agent (Sidecar + 3x-ui)"
    echo -e " 3. Uninstall / Clean Up"
    echo -e " 4. Switch Language / 切换语言"
    echo -e " 0. Exit"
    echo -e "-------------------------------------------"
    read -p "Select: " opt

    case $opt in
        1) check_root; install_master ;;
        2) check_root; install_agent ;;
        3) check_root; uninstall ;;
        4) set_language; show_menu ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
