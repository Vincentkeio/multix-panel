#!/bin/bash

# ==============================================================================
# MultiX Cluster Manager - v8.0 (Production)
# ==============================================================================
# 架构：Docker Host Network + Python Flask + Vue3 Element Plus
# 特性：单端口复用 / 宿主机状态透传 / 真实 BBR 检测 / 3x-ui 深度集成
# ==============================================================================

# --- [ 全局配置初始化 ] ---
INSTALL_PATH="/opt/multix"
CONFIG_FILE="${INSTALL_PATH}/config.json"

# 默认配置 (如果配置文件不存在)
DEFAULT_PORT=7575
DEFAULT_TOKEN="multix_secret_token"
DEFAULT_USER="admin"
DEFAULT_PASS="admin123"

# --- [ 颜色定义 ] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# ==============================================================================
#  工具函数
# ==============================================================================

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请使用 root 权限运行此脚本！${PLAIN}" && exit 1
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}>>> 检测到 Docker 未安装，正在自动安装...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi
}

# 读取或初始化配置
init_config() {
    mkdir -p ${INSTALL_PATH}
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"port\": $DEFAULT_PORT, \"token\": \"$DEFAULT_TOKEN\", \"username\": \"$DEFAULT_USER\", \"password\": \"$DEFAULT_PASS\"}" > $CONFIG_FILE
    fi
    # 从文件读取配置到变量
    CFG_PORT=$(grep -oP '(?<="port": )[0-9]+' $CONFIG_FILE)
    CFG_TOKEN=$(grep -oP '(?<="token": ")[^"]+' $CONFIG_FILE)
    CFG_USER=$(grep -oP '(?<="username": ")[^"]+' $CONFIG_FILE)
    CFG_PASS=$(grep -oP '(?<="password": ")[^"]+' $CONFIG_FILE)
}

# ==============================================================================
#  1. Master (主控) 安装逻辑
# ==============================================================================
install_master() {
    check_root
    check_docker
    init_config
    
    echo -e "${GREEN}>>> 正在构建 MultiX Master 主控端...${PLAIN}"
    echo -e "    当前端口: ${CFG_PORT}"
    echo -e "    当前用户: ${CFG_USER}"
    
    mkdir -p ${INSTALL_PATH}/master
    cd ${INSTALL_PATH}/master

    # 1. 写入 app.py (后端 + 前端)
    # 注意：这里使用 'EOF' 防止 shell 解析 Python 内部变量，但我们需要 Shell 解析 Config 变量
    # 解决方案：后端读取 config.json，前端 HTML 纯静态
    
    cat > app.py <<'EOF'
import json, time, os, psutil, subprocess
from flask import Flask, request, jsonify, make_response
from functools import wraps

# --- 配置加载 ---
CONFIG_PATH = "/app/config.json"
def load_config():
    with open(CONFIG_PATH, 'r') as f: return json.load(f)

def save_config(cfg):
    with open(CONFIG_PATH, 'w') as f: json.dump(cfg, f, indent=4)

app = Flask(__name__)
AGENTS = {}

# --- 认证装饰器 ---
def auth_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        cfg = load_config()
        if not auth or auth.username != cfg['username'] or auth.password != cfg['password']:
            return make_response('Could not verify', 401, {'WWW-Authenticate': 'Basic realm="Login Required"'})
        return f(*args, **kwargs)
    return decorated

# --- 核心 UI (Vue3 + Element Plus) ---
# 解决模板冲突：直接返回字符串，不经过 Jinja2 渲染
HTML_UI = r"""
<!DOCTYPE html>
<html class="dark">
<head>
    <title>MultiX Manager</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <link rel="stylesheet" href="https://unpkg.com/element-plus/dist/index.css" />
    <link rel="stylesheet" href="https://unpkg.com/element-plus/theme-chalk/dark/css-vars.css">
    <script src="https://unpkg.com/element-plus"></script>
    <script src="https://unpkg.com/@element-plus/icons-vue"></script>
    <style>
        body { margin: 0; background: #141414; color: #E5EAF3; font-family: 'Segoe UI', sans-serif; }
        .el-aside { background: #1d1e1f; border-right: 1px solid #363637; height: 100vh; }
        .el-header { background: #1d1e1f; border-bottom: 1px solid #363637; display: flex; align-items: center; justify-content: space-between; }
        .logo { font-size: 18px; font-weight: bold; color: #409EFF; display: flex; align-items: center; justify-content: center; height: 60px; border-bottom: 1px solid #363637;}
        .stat-card { background: #252526; border: 1px solid #363637; margin-bottom: 20px; color: #fff; }
        .status-dot { height: 8px; width: 8px; border-radius: 50%; display: inline-block; margin-right: 5px; }
        .online { background: #67C23A; box-shadow: 0 0 5px #67C23A; }
        .offline { background: #909399; }
        .ip-tag { font-size: 11px; margin-right: 5px; background: #333; padding: 2px 5px; border-radius: 4px; }
    </style>
</head>
<body>
    <div id="app">
        <el-container>
            <el-aside width="220px">
                <div class="logo"><el-icon style="margin-right:8px"><Data_Line /></el-icon> MultiX v8.0</div>
                <el-menu active-text-color="#409EFF" background-color="#1d1e1f" text-color="#fff" :default-active="activeTab" @select="handleSelect" style="border-right:none">
                    <el-menu-item index="dashboard"><el-icon><Odometer /></el-icon><span>仪表盘 (Dashboard)</span></el-menu-item>
                    <el-menu-item index="cluster"><el-icon><Connection /></el-icon><span>节点监控 (Cluster)</span></el-menu-item>
                    <el-menu-item index="settings"><el-icon><Setting /></el-icon><span>系统设置 (Settings)</span></el-menu-item>
                </el-menu>
            </el-aside>
            <el-container>
                <el-header>
                    <div><el-tag type="info" effect="dark">Role: Master</el-tag></div>
                    <div style="font-size:12px; color:#909399">Running on Host Network</div>
                </el-header>
                <el-main>
                    <div v-if="activeTab === 'dashboard'">
                        <h3><el-icon><Monitor /></el-icon> 主控端状态 (Localhost)</h3>
                        <el-row :gutter="20" style="margin-top:20px">
                            <el-col :span="6" v-for="(val, key) in masterStats" :key="key">
                                <el-card class="stat-card" shadow="hover">
                                    <div style="text-align:center">
                                        <el-progress type="dashboard" :percentage="val.pct" :color="val.color"></el-progress>
                                        <div style="margin-top:10px; font-weight:bold">{{ val.label }}</div>
                                        <div style="font-size:12px; color:#aaa">{{ val.text }}</div>
                                    </div>
                                </el-card>
                            </el-col>
                        </el-row>
                    </div>

                    <div v-if="activeTab === 'cluster'">
                        <h3><el-icon><Connection /></el-icon> 在线节点 ({{ Object.keys(agents).length }})</h3>
                        <el-empty v-if="Object.keys(agents).length === 0" description="暂无节点连接"></el-empty>
                        <el-row :gutter="20">
                            <el-col :span="8" v-for="(agent, ip) in agents" :key="ip">
                                <el-card class="stat-card" shadow="hover">
                                    <template #header>
                                        <div style="display:flex; justify-content:space-between; align-items:center">
                                            <span><span class="status-dot" :class="agent.status"></span>{{ agent.name }}</span>
                                            <el-tag size="small" :type="agent.bbr ? 'success' : 'info'">{{ agent.bbr ? 'BBR On' : 'No BBR' }}</el-tag>
                                        </div>
                                    </template>
                                    <div style="font-size:12px; margin-bottom:10px">
                                        <div style="margin-bottom:5px"><span class="ip-tag">IPv4</span> {{ agent.ipv4 || 'N/A' }}</div>
                                        <div style="margin-bottom:5px"><span class="ip-tag">IPv6</span> {{ agent.ipv6 || 'N/A' }}</div>
                                    </div>
                                    <el-progress :percentage="agent.cpu" :stroke-width="6" :format="p=>'CPU '+p+'%'" style="margin-bottom:5px"></el-progress>
                                    <el-progress :percentage="agent.mem" :stroke-width="6" :format="p=>'MEM '+p+'%'" color="#e6a23c" style="margin-bottom:15px"></el-progress>
                                    <el-button-group style="width:100%; display:flex">
                                        <el-button type="primary" plain size="small" style="flex:1" @click="openXui(agent.ipv4 || ip, agent.xport)">3X-UI 面板</el-button>
                                        <el-button type="danger" plain size="small" icon="Delete" @click="removeAgent(ip)"></el-button>
                                    </el-button-group>
                                </el-card>
                            </el-col>
                        </el-row>
                    </div>

                    <div v-if="activeTab === 'settings'">
                        <h3><el-icon><Setting /></el-icon> 系统设置</h3>
                        <el-card class="stat-card" style="max-width: 600px">
                            <el-form label-width="120px" label-position="left">
                                <el-form-item label="主控端口"><el-input v-model="settings.port" type="number"></el-input></el-form-item>
                                <el-form-item label="通讯密钥"><el-input v-model="settings.token" show-password></el-input></el-form-item>
                                <el-form-item label="管理员用户"><el-input v-model="settings.username"></el-input></el-form-item>
                                <el-form-item label="管理员密码"><el-input v-model="settings.password" show-password></el-input></el-form-item>
                                <el-form-item>
                                    <el-button type="primary" @click="saveSettings">保存并重启面板</el-button>
                                </el-form-item>
                            </el-form>
                        </el-card>
                    </div>
                </el-main>
            </el-container>
        </el-container>
    </div>
    <script>
        const { createApp, ref, onMounted, reactive } = Vue;
        const app = createApp({
            setup() {
                const activeTab = ref('dashboard');
                const agents = ref({});
                const masterStats = ref({});
                const settings = reactive({port:7575, token:'', username:'', password:''});

                const handleSelect = (key) => activeTab.value = key;
                
                const fetchAgents = async () => {
                    try { agents.value = await (await fetch('/api/agents')).json(); } catch(e){}
                };
                const fetchStats = async () => {
                    try { 
                        const d = await (await fetch('/api/stats')).json();
                        masterStats.value = {
                            cpu: {label:'CPU', pct:d.cpu, color:'#409EFF', text: d.cpu_model},
                            mem: {label:'Memory', pct:d.mem, color:'#67C23A', text: d.mem_total},
                            disk: {label:'Disk', pct:d.disk, color:'#E6A23C', text: 'Root /'},
                            swap: {label:'Swap', pct:d.swap, color:'#F56C6C', text: 'Virtual Mem'}
                        };
                    } catch(e){}
                };
                const fetchSettings = async () => {
                     try { Object.assign(settings, await (await fetch('/api/settings')).json()); } catch(e){}
                }
                const saveSettings = async () => {
                    if(!confirm('修改配置会导致面板重启，确定吗？')) return;
                    await fetch('/api/settings', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(settings)});
                    alert('配置已保存，容器正在重启，请稍后刷新页面。');
                };
                const openXui = (ip, port) => window.open(`http://${ip}:${port}`, '_blank');
                const removeAgent = (ip) => delete agents.value[ip]; // 仅前端临时删除

                onMounted(() => {
                    setInterval(() => { fetchAgents(); fetchStats(); }, 3000);
                    fetchAgents(); fetchStats(); fetchSettings();
                });
                return { activeTab, handleSelect, agents, masterStats, settings, saveSettings, openXui, removeAgent };
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
@auth_required
def index(): return HTML_UI

@app.route('/api/stats')
@auth_required
def stats():
    # 获取宿主机 CPU/内存 (需要 --privileged 或挂载)
    return jsonify({
        'cpu': int(psutil.cpu_percent(interval=None)),
        'cpu_model': subprocess.getoutput("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2").strip()[:20],
        'mem': int(psutil.virtual_memory().percent),
        'mem_total': f"{round(psutil.virtual_memory().total / (1024**3), 1)} GB",
        'disk': int(psutil.disk_usage('/').percent),
        'swap': int(psutil.swap_memory().percent)
    })

@app.route('/api/agents')
@auth_required
def list_agents():
    now = time.time()
    for ip in AGENTS:
        if now - AGENTS[ip]['last_seen'] > 15: AGENTS[ip]['status'] = 'offline'
    return jsonify(AGENTS)

@app.route('/api/heartbeat', methods=['POST'])
def heartbeat():
    cfg = load_config()
    # Token 验证
    if request.headers.get('Authorization') != cfg['token']: 
        return jsonify({'error': 'Invalid Token'}), 403
    
    data = request.json
    ip = request.remote_addr # 获取连接 IP
    
    # 如果 Agent 汇报了自己的公网 IP，优先使用
    display_ip = data.get('ipv4') or ip

    AGENTS[display_ip] = {
        'name': data.get('name'),
        'cpu': data.get('cpu'),
        'mem': data.get('mem'),
        'bbr': data.get('bbr'),
        'ipv4': data.get('ipv4'),
        'ipv6': data.get('ipv6'),
        'xport': data.get('x_port', 2053),
        'status': 'online',
        'last_seen': time.time()
    }
    return jsonify({'status': 'ok'})

@app.route('/api/settings', methods=['GET', 'POST'])
@auth_required
def settings_api():
    if request.method == 'GET': return jsonify(load_config())
    new_cfg = request.json
    save_config(new_cfg)
    # 触发容器重启 (简单的 suicide 方式，Docker restart policy 会拉起)
    def restart_soon():
        time.sleep(1)
        os._exit(1)
    import threading
    threading.Thread(target=restart_soon).start()
    return jsonify({'status': 'restarting'})

if __name__ == '__main__':
    cfg = load_config()
    # 监听 0.0.0.0 端口
    app.run(host='0.0.0.0', port=cfg['port'])
EOF

    # 2. Dockerfile
    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask psutil" >> Dockerfile
    echo "COPY app.py /app.py" >> Dockerfile
    echo "CMD [\"python\", \"/app.py\"]" >> Dockerfile

    # 3. 启动容器 (关键：Network Host + Privileged)
    echo -e "${YELLOW}>>> 正在启动 Master 容器 (Host Network)...${PLAIN}"
    docker build -t multix-master .
    docker rm -f multix-master 2>/dev/null
    
    # 挂载 config.json 持久化
    docker run -d \
        --name multix-master \
        --network host \
        --privileged \
        --restart always \
        -v ${CONFIG_FILE}:/app/config.json \
        multix-master

    echo -e "${GREEN}>>> 安装成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s4 ifconfig.me):${CFG_PORT}"
    echo -e "账号: ${CFG_USER}"
    echo -e "密码: ${CFG_PASS}"
}

# ==============================================================================
#  2. Agent (被控) 安装逻辑
# ==============================================================================
install_agent() {
    check_root
    check_docker
    
    echo -e "${GREEN}>>> 正在构建 MultiX Agent (集成 3x-ui)...${PLAIN}"
    
    # 交互输入
    read -p "请输入 Master IP: " M_IP
    read -p "请输入 Master 端口 [默认 $DEFAULT_PORT]: " M_PORT
    M_PORT=${M_PORT:-$DEFAULT_PORT}
    read -p "请输入通讯 Token: " U_TOKEN
    
    mkdir -p ${INSTALL_PATH}/agent
    cd ${INSTALL_PATH}/agent

    # 1. Agent 脚本 (真实状态采集)
    cat > agent.py <<EOF
import time, requests, psutil, os, socket, subprocess

MASTER_URL = "http://${M_IP}:${M_PORT}/api/heartbeat"
TOKEN = "${U_TOKEN}"
HOSTNAME = socket.gethostname()

def get_public_ip(ver=4):
    try:
        url = "https://api64.ipify.org?format=json" if ver==6 else "https://api.ipify.org?format=json"
        return requests.get(url, timeout=3).json()['ip']
    except: return None

def check_bbr():
    try:
        res = subprocess.getoutput("sysctl net.ipv4.tcp_congestion_control")
        return "bbr" in res
    except: return False

def loop():
    # 缓存静态信息
    my_ipv4 = get_public_ip(4)
    my_ipv6 = get_public_ip(6)
    my_bbr = check_bbr()
    
    print(f"Agent Ready. IPv4: {my_ipv4}, BBR: {my_bbr}")

    while True:
        stats = {
            'name': HOSTNAME,
            'cpu': int(psutil.cpu_percent(interval=1)),
            'mem': int(psutil.virtual_memory().percent),
            'bbr': my_bbr,
            'ipv4': my_ipv4,
            'ipv6': my_ipv6,
            'x_port': int(os.getenv('XUI_PORT', 2053))
        }
        try:
            requests.post(MASTER_URL, json=stats, headers={'Authorization': TOKEN}, timeout=5)
        except Exception as e:
            print(f"Connection Error: {e}")
        time.sleep(5)

if __name__ == '__main__':
    loop()
EOF

    # 2. Dockerfile
    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install requests psutil" >> Dockerfile
    echo "COPY agent.py /agent.py" >> Dockerfile
    echo "CMD [\"python\", \"/agent.py\"]" >> Dockerfile

    # 3. Docker Compose (Host Mode)
    cat > docker-compose.yml <<EOF
services:
  xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    network_mode: "host"
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
    restart: always
    environment:
      XUI_PORT: 2053
  
  multix-agent:
    build: .
    container_name: multix-agent
    network_mode: "host"
    privileged: true
    restart: always
    environment:
      XUI_PORT: 2053
EOF

    # 冲突清理
    if [ "$(docker ps -aq -f name=3x-ui)" ]; then
        echo -e "${YELLOW}警告: 发现旧版 3x-ui 容器，正在停止并移除以防止端口冲突...${PLAIN}"
        docker rm -f 3x-ui multix-agent &>/dev/null
    fi

    echo -e "${YELLOW}正在启动服务...${PLAIN}"
    docker compose up -d --build
    echo -e "${GREEN}>>> Agent 部署完成！${PLAIN}"
    echo -e "请在 Master 面板查看上线状态。"
}

# ==============================================================================
#  3. 卸载与管理
# ==============================================================================
uninstall() {
    echo -e "${RED}危险: 确定要卸载吗？(y/n)${PLAIN}"
    read -p "输入: " c
    if [[ "$c" == "y" ]]; then
        docker rm -f multix-master multix-agent 3x-ui 2>/dev/null
        rm -rf ${INSTALL_PATH}
        echo -e "${GREEN}卸载完成。${PLAIN}"
    fi
}

show_menu() {
    clear
    echo -e "================================================="
    echo -e "   MultiX Cluster Manager ${YELLOW}[v8.0 Host Mode]${PLAIN}"
    echo -e "================================================="
    echo -e " 1. 安装 Master (主控端 Web 面板)"
    echo -e " 2. 安装 Agent  (监控端 + 3x-ui)"
    echo -e " 3. 卸载 / 清理环境"
    echo -e " 0. 退出"
    echo -e "================================================="
    read -p "请选择: " opt
    case $opt in
        1) install_master ;;
        2) install_agent ;;
        3) uninstall ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
