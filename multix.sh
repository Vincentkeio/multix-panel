#!/bin/bash

# ==============================================================================
# MultiX Cluster Manager - v8.2 (Stable)
# ==============================================================================
# 修复：Docker 安装状态强校验
# 修复：卸载逻辑优化
# 修复：安装过程中的错误阻断机制
# ==============================================================================

INSTALL_PATH="/opt/multix"
CONFIG_FILE="${INSTALL_PATH}/config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# ==============================================================================
#  核心检查函数 (Fix: 增加错误阻断)
# ==============================================================================

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请使用 root 权限运行此脚本！${PLAIN}" && exit 1
}

check_docker() {
    echo -e "${YELLOW}>>> 正在检查 Docker 环境...${PLAIN}"
    
    # 1. 尝试调用 docker 命令
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}>>> 未检测到 Docker，正在执行自动安装...${PLAIN}"
        
        # 使用官方脚本安装
        curl -fsSL https://get.docker.com | bash
        
        # 再次检查
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}>>> 严重错误：Docker 安装失败！${PLAIN}"
            echo -e "${RED}>>> 可能原因：网络连接 Docker 官方源超时。${PLAIN}"
            echo -e "${RED}>>> 请尝试手动安装 Docker 后再运行此脚本。${PLAIN}"
            exit 1
        fi
        
        echo -e "${GREEN}>>> Docker 安装成功！${PLAIN}"
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}>>> Docker 已安装。${PLAIN}"
    fi

    # 2. 检查 Docker 服务是否运行
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${YELLOW}>>> Docker 服务未运行，正在启动...${PLAIN}"
        systemctl start docker
        if ! docker ps > /dev/null 2>&1; then
             echo -e "${RED}>>> 错误：无法启动 Docker 服务，请检查系统日志 (journalctl -u docker)。${PLAIN}"
             exit 1
        fi
    fi
}

# ==============================================================================
#  1. Master 安装逻辑
# ==============================================================================
install_master() {
    check_root
    check_docker  # 这里如果失败会直接 exit，不会往下走
    
    echo -e "${GREEN}>>> 正在构建 MultiX Master...${PLAIN}"
    mkdir -p ${INSTALL_PATH}/master
    
    # 初始化配置
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"port": 7575, "token": "multix_token", "username": "admin", "password": "admin123"}' > $CONFIG_FILE
    fi

    # 写入 app.py
    cat > ${INSTALL_PATH}/master/app.py <<'EOF'
import json, time, secrets, psutil
from flask import Flask, request, jsonify, render_template_string, session

# 加载配置
CONFIG_FILE = '/app/config.json'
def load_cfg():
    try:
        with open(CONFIG_FILE) as f: return json.load(f)
    except: return {"port":7575}

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)
AGENTS = {}

# HTML 模板
HTML_TEMPLATE = r"""
<!DOCTYPE html>
<html class="dark">
<head>
<meta charset="UTF-8"><title>MultiX Manager</title>
<script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
<link rel="stylesheet" href="https://unpkg.com/element-plus/dist/index.css" />
<link rel="stylesheet" href="https://unpkg.com/element-plus/theme-chalk/dark/css-vars.css">
<script src="https://unpkg.com/element-plus"></script>
<style>body{margin:0;background:#141414;color:#fff;font-family:sans-serif}.login-box{width:300px;margin:100px auto;padding:30px;background:#1d1e1f;border:1px solid #333;text-align:center}</style>
</head>
<body>
<div id="app">
 <div v-if="!isLoggedIn" class="login-box">
  <h3>MultiX Login</h3>
  <el-input v-model="f.u" placeholder="User" style="margin-bottom:10px"></el-input>
  <el-input v-model="f.p" type="password" placeholder="Pass" show-password style="margin-bottom:20px"></el-input>
  <el-button type="primary" style="width:100%" @click="login">Login</el-button>
 </div>
 <div v-else style="padding:20px">
  <div style="display:flex;justify-content:space-between;margin-bottom:20px">
   <h3>MultiX Manager <el-tag>Online</el-tag></h3>
   <el-button type="danger" size="small" @click="logout">Logout</el-button>
  </div>
  <el-row :gutter="20">
   <el-col :span="8" v-for="(a,ip) in agents" :key="ip">
    <el-card style="background:#252526;border:1px solid #333;color:#fff">
     <template #header>
      <div style="display:flex;justify-content:space-between">
       <span>{{a.name}}</span>
       <el-tag size="small" :type="a.status=='online'?'success':'info'">{{a.status}}</el-tag>
      </div>
     </template>
     <div>IP: {{a.ipv4}}</div>
     <div>BBR: <span :style="{color:a.bbr?'lightgreen':'red'}">{{a.bbr?'ON':'OFF'}}</span></div>
     <div style="margin-top:10px">CPU: {{a.cpu}}%</div>
     <el-button style="width:100%;margin-top:15px" type="primary" plain size="small" @click="open(a.ipv4, a.xport)">Open 3X-UI</el-button>
    </el-card>
   </el-col>
  </el-row>
  <el-empty v-if="Object.keys(agents).length==0" description="No Agents Connected"></el-empty>
 </div>
</div>
<script>
const {createApp,ref,reactive,onMounted}=Vue;
createApp({
 setup(){
  const isLoggedIn=ref(false);
  const f=reactive({u:'',p:''});
  const agents=ref({});
  const check=async()=>{try{isLoggedIn.value=(await(await fetch('/api/auth')).json()).ok;if(isLoggedIn.value)loop();}catch{}};
  const login=async()=>{try{if((await(await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(f)})).json()).ok){isLoggedIn.value=true;loop();}}catch{}};
  const logout=async()=>{await fetch('/api/logout');isLoggedIn.value=false;};
  const loop=()=>{fetch('/api/data').then(r=>r.json()).then(d=>agents.value=d);setTimeout(loop,3000);};
  const open=(i,p)=>window.open(`http://${i}:${p}`);
  onMounted(check);
  return {isLoggedIn,f,login,logout,agents,open};
 }
}).use(ElementPlus).mount('#app');
</script></body></html>
"""

@app.route('/')
def idx(): return render_template_string(HTML_TEMPLATE)
@app.route('/api/auth')
def chk(): return jsonify({'ok':'u' in session})
@app.route('/api/login', methods=['POST'])
def log():
 c=load_cfg(); d=request.json
 if d['u']==c['username'] and d['p']==c['password']: session['u']=1; return jsonify({'ok':True})
 return jsonify({'ok':False})
@app.route('/api/logout')
def out(): session.pop('u',None); return jsonify({'ok':True})
@app.route('/api/data')
def dat():
 if 'u' not in session: return jsonify({})
 t=time.time()
 for k in AGENTS:
  if t-AGENTS[k]['t']>15: AGENTS[k]['status']='offline'
 return jsonify(AGENTS)
@app.route('/api/heartbeat', methods=['POST'])
def hb():
 c=load_cfg(); d=request.json
 if request.headers.get('Authorization')!=c['token']: return jsonify({}),403
 ip=d.get('ipv4') or request.remote_addr
 AGENTS[ip]={'name':d.get('name'),'cpu':d.get('cpu'),'bbr':d.get('bbr'),'ipv4':ip,'xport':d.get('x_port',2053),'status':'online','t':time.time()}
 return jsonify({'status':'ok'})
if __name__=='__main__':
 c=load_cfg()
 app.run(host='0.0.0.0', port=c['port'])
EOF

    # Dockerfile
    echo 'FROM python:3.9-slim
RUN pip install flask psutil
COPY app.py /app.py
CMD ["python", "/app.py"]' > ${INSTALL_PATH}/master/Dockerfile

    # 构建与启动
    echo -e "${YELLOW}>>> 正在构建容器镜像 (可能需要几分钟)...${PLAIN}"
    cd ${INSTALL_PATH}/master
    
    # 增加 set -e 确保出错即停
    if ! docker build -t multix-master .; then
        echo -e "${RED}>>> 镜像构建失败！请检查网络是否能连接 Docker Hub。${PLAIN}"
        exit 1
    fi
    
    docker rm -f multix-master 2>/dev/null
    
    docker run -d \
        --name multix-master \
        --network host \
        --privileged \
        --restart always \
        -v ${INSTALL_PATH}/config.json:/app/config.json \
        multix-master

    echo -e "${GREEN}==========================================${PLAIN}"
    echo -e "${GREEN} 安装成功！${PLAIN}"
    echo -e " 管理面板: http://$(curl -s4 ifconfig.me):7575"
    echo -e " 默认账户: admin"
    echo -e " 默认密码: admin123"
    echo -e "${GREEN}==========================================${PLAIN}"
}

# ==============================================================================
#  2. 卸载逻辑 (Fix: 清理不干净的问题)
# ==============================================================================
uninstall() {
    echo -e "${RED}警告：此操作将删除 Master 和 Agent 容器。${PLAIN}"
    read -p "是否同时卸载 Docker 引擎？(y/n，推荐 n): " del_docker
    
    echo -e "${YELLOW}>>> 正在停止并删除容器...${PLAIN}"
    docker rm -f multix-master multix-agent 3x-ui 2>/dev/null
    
    echo -e "${YELLOW}>>> 正在清理数据文件...${PLAIN}"
    rm -rf ${INSTALL_PATH}
    
    if [[ "$del_docker" == "y" ]]; then
        echo -e "${YELLOW}>>> 正在卸载 Docker...${PLAIN}"
        if command -v apt-get &>/dev/null; then
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd
        elif command -v yum &>/dev/null; then
            yum remove -y docker-ce docker-ce-cli containerd.io
        fi
        echo -e "${GREEN}>>> Docker 已卸载。${PLAIN}"
    fi
    
    echo -e "${GREEN}>>> 卸载完成。${PLAIN}"
}

# ==============================================================================
#  菜单
# ==============================================================================
show_menu() {
    clear
    echo -e "==========================================="
    echo -e " MultiX Manager v8.2 ${YELLOW}(Fix Docker)${PLAIN}"
    echo -e "==========================================="
    echo -e " 1. 安装 Master (主控)"
    echo -e " 2. 安装 Agent (被控)"
    echo -e " 3. 卸载"
    echo -e " 0. 退出"
    echo -e "==========================================="
    read -p " 请输入: " num
    case $num in
        1) install_master ;;
        2) check_root; check_docker; echo "Agent 安装逻辑同上..." ;; # 占位
        3) check_root; uninstall ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

show_menu
