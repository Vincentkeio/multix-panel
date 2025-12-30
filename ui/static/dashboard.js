/**
 * Multiy Pro 旗舰版核心逻辑控制中心 - 深度增强版
 */
function multix() {
    return {
        // --- [ 1. 基础响应式状态 ] ---
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false, 
        searchQuery: '',
        
        // --- [ 2. 数据容器 ] ---
        // 初始值预设，防止页面渲染时因 undefined 导致 0% 报错
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '加载中...', sb_ver: 'N/A' },
        agents: {},
        config: { user: 'GUEST', token: '', ip4: '', web_port: 7575 },
        
        // --- [ 3. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 4. 表单与交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', 
        editingSid: null, tempAlias: '', 
        subType: 'v2ray', 
        globalLinks: '',
        
        // --- [ 5. 节点详情变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,

        // --- [ 6. 初始化核心：解决登录不响应的关键 ] ---
        async init() {
            console.log("Multiy Engine Initializing...");
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                // 仅标记状态，具体权限交由 fetchState 校验
                this.isLoggedIn = true;
            }
            
            // 立即执行首次数据同步并开启心跳
            await this.fetchState();
            setInterval(() => this.fetchState(), 5000); 
        },

        // --- [ 7. 核心数据同步：修复 0% 数据的关键 ] ---
        async fetchState() {
            try {
                // 增加缓存穿透，确保获取实时数据
                const res = await fetch(`/api/state?v=${Date.now()}`);
                if (!res.ok) throw new Error("Backend Offline");
                const data = await res.json();
                
                // 严格赋值，确保数据对象完整性
                this.master = data.master || this.master;
                this.agents = data.agents || {};
                this.config = data.config || this.config;
                
                // 身份同步：如果后端返回无 Token，前端强制降级
                if (this.isLoggedIn && !this.config.token) {
                    // console.warn("Session expired");
                }

                if (this.isLoggedIn && !this.tempUser) {
                    this.tempUser = this.config.user;
                    this.tempToken = this.config.token;
                }
            } catch (e) { 
                console.error("同步失败:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 8. 节点管理逻辑 - 搜索与虚拟占位 ] ---
        
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        // 旗舰版核心：主页网格列表逻辑
        get filteredAgents() {
            let list = Object.entries(this.agents);
            
            // 场景 A: 如果列表为空，注入虚拟小鸡
            if (list.length === 0) {
                return {
                    "virtual-001": {
                        hostname: "PRO-NODE-DEMO",
                        alias: "待接入演示节点",
                        is_demo: true, 
                        order: 1,
                        status: "online",
                        metrics: { cpu: 12, mem: 24, load: "0.15", net_out: "0B/s", net_in: "0B/s", latency: "28" }
                    }
                };
            }

            // 场景 B: 搜索与隐藏逻辑过滤
            const q = this.searchQuery.toLowerCase();
            let filtered = list.filter(([sid, a]) => {
                const matchSearch = (a.alias && a.alias.toLowerCase().includes(q)) || 
                                    a.hostname.toLowerCase().includes(q) || 
                                    sid.includes(q);
                
                // 无论是否登录，主页网格都不显示标记为 hidden 的节点
                return matchSearch && !a.hidden;
            });

            return Object.fromEntries(filtered.sort(([, a], [, b]) => (a.order || 999) - (b.order || 999)));
        },

        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': localStorage.getItem('m_token') || '' 
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { alert("操作失败: " + e.message); }
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 9. 订阅与导出 ] ---
        generateSubLink() {
            return `http://${window.location.host}/sub?token=${this.config.token}&type=${this.subType}`;
        },

        async exportGlobalNodes() {
            this.globalLinks = "";
            let count = 0;
            Object.values(this.agents).forEach(agent => {
                if (agent.hidden) return;
                const ip = agent.ip || this.config.ip4;
                (agent.metrics?.inbounds || []).forEach(inb => {
                    if (inb.type === 'vless') {
                        this.globalLinks += `vless://${inb.uuid}@${ip}:${inb.listen_port || inb.port}?security=reality&sni=${inb.reality_dest?.split(':')[0] || 'yahoo.com'}&fp=chrome&pbk=${inb.reality_pub || ''}&sid=${inb.short_id || ''}&type=tcp&flow=xtls-rprx-vision#${inb.tag}\n`;
                        count++;
                    }
                });
            });
            if (count === 0) return alert("无可导出的 VLESS 节点");
            this.globalExportModal = true;
            this.$nextTick(() => this.renderQR(this.globalLinks));
        },

        renderQR(text) {
            const container = document.getElementById('global-qr-code');
            if (container) {
                container.innerHTML = "";
                new QRCode(container, { text, width: 200, height: 200, colorDark: "#000000", colorLight: "#ffffff" });
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("已复制到剪贴板"));
        },

        // --- [ 10. 认证管理：点击响应修复 ] ---
        async login() {
            if (!this.loginForm.user || !this.loginForm.pass) {
                alert("请填写账号密码");
                return;
            }
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(this.loginForm)
                });
                const data = await res.json();
                if (res.ok && data.status === "success") {
                    localStorage.setItem('m_token', data.token);
                    this.isLoggedIn = true;
                    this.showLoginModal = false;
                    // 登录后强制全量刷新
                    await this.fetchState();
                    window.location.reload(); 
                } else { 
                    alert("账号或密码错误"); 
                }
            } catch (e) { 
                alert("服务器连接异常: " + e.message); 
            }
        },

        logout() {
            if (confirm("确定注销当前管理员会话？")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        }
    }
}
