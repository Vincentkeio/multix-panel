/**
 * Multiy Pro 旗舰版核心逻辑控制中心
 */
function multix() {
    return {
        // --- [ 1. 基础响应式状态 ] ---
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false, // 控制主控状态栏 Token 遮掩
        searchQuery: '',
        
        // --- [ 2. 数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '加载中...', sb_ver: 'N/A' },
        agents: {},
        config: { user: '', token: '', ip4: '', web_port: 7575 },
        
        // --- [ 3. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 4. 表单与交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', // 管理中心安全凭据
        editingSid: null, tempAlias: '', // 节点别名修改
        subType: 'v2ray', 
        globalLinks: '',
        
        // --- [ 5. 节点详情 (Agent) 变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,

        // --- [ 6. 初始化与心跳 ] ---
        init() {
            // 检查本地持久化凭据
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
                // 立即执行首次数据同步
                this.fetchState();
            }
            
            // 开启高频心跳：5秒同步一次硬件与节点指标
            setInterval(() => this.fetchState(), 5000);
        },

        // --- [ 7. 核心数据同步逻辑 ] ---
        async fetchState() {
            try {
                const res = await fetch('/api/state');
                if (!res.ok) throw new Error("Backend Offline");
                
                const data = await res.json();
                
                // 更新主控与节点数据
                this.master = data.master;
                this.agents = data.agents;
                this.config = data.config;
                
                // 当管理员进入管理中心时，初始化表单默认值
                if (this.isLoggedIn && !this.tempUser) {
                    this.tempUser = this.config.user;
                    this.tempToken = this.config.token;
                }
            } catch (e) { 
                console.error("Multiy 数据同步失败:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 8. 节点管理与排序 ] ---
        get sortedAgents() {
            // 根据 order 字段进行升序排列，未定义 order 的排在最后
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        // 计算属性：过滤后的节点列表 (用于搜索框)
        get filteredAgents() {
            if (!this.searchQuery) return this.sortedAgents;
            const q = this.searchQuery.toLowerCase();
            return Object.fromEntries(
                Object.entries(this.agents).filter(([sid, a]) => 
                    (a.alias && a.alias.toLowerCase().includes(q)) || 
                    a.hostname.toLowerCase().includes(q) || 
                    sid.includes(q)
                )
            );
        },

        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': this.config.token 
                    },
                    body: JSON.stringify({ sid, action, value }) // 修正原代码拼写错误
                });
                if (res.ok) await this.fetchState();
            } catch (e) { 
                alert("操作指令下发失败"); 
            }
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 9. 超级订阅与全局导出 ] ---
        generateSubLink() {
            const host = window.location.host;
            // 动态构建订阅链接
            return `http://${host}/sub?token=${this.config.token}&type=${this.subType}`;
        },

        async exportGlobalNodes() {
            this.globalLinks = "";
            let count = 0;
            
            Object.values(this.agents).forEach(agent => {
                if (agent.hidden) return; // 跳过隐藏节点
                const ip = agent.ip || this.config.ip4;
                const inbounds = agent.metrics?.inbounds || [];
                
                inbounds.forEach(inb => {
                    if (inb.type === 'vless') {
                        // 构建标准 VLESS Reality 链接
                        const link = `vless://${inb.uuid}@${ip}:${inb.listen_port || inb.port}?security=reality&sni=${inb.reality_dest?.split(':')[0] || 'yahoo.com'}&fp=chrome&pbk=${inb.reality_pub || ''}&sid=${inb.short_id || ''}&type=tcp&flow=xtls-rprx-vision#${inb.tag}`;
                        this.globalLinks += link + "\n";
                        count++;
                    }
                });
            });

            if (count === 0) {
                alert("暂无活跃的 VLESS 节点可供导出");
                return;
            }

            this.globalExportModal = true;
            // 延迟渲染二维码，确保 DOM 节点已挂载
            setTimeout(() => this.renderQR(this.globalLinks), 100);
        },

        renderQR(text) {
            const container = document.getElementById('global-qr-code');
            if (container) {
                container.innerHTML = "";
                new QRCode(container, { 
                    text: text, 
                    width: 200, 
                    height: 200, 
                    colorDark: "#000000", 
                    colorLight: "#ffffff",
                    correctLevel: QRCode.CorrectLevel.L
                });
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => {
                // 使用原生提示
                const btn = event.target;
                const oldText = btn.innerText;
                btn.innerText = "COPIED!";
                setTimeout(() => btn.innerText = oldText, 2000);
            });
        },

        // --- [ 10. 登录管理系统 ] ---
        async login() {
            if (!this.loginForm.user || !this.loginForm.pass) return alert("请输入完整信息");
            
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user: this.loginForm.user, pass: this.loginForm.pass })
                });

                const data = await res.json();
                if (res.ok && data.status === "success") {
                    localStorage.setItem('m_token', data.token);
                    this.isLoggedIn = true;
                    this.showLoginModal = false;
                    await this.fetchState(); // 立即同步管理员权限下的数据
                } else { 
                    alert("认证失败：用户名或密码错误"); 
                }
            } catch (e) {
                alert("连接主控后端超时");
            }
        },

        logout() {
            if (confirm("确定要注销管理员会话吗？")) {
                localStorage.removeItem('m_token');
                window.location.reload(); // 刷新以清理内存中的敏感变量
            }
        }
    }
}
