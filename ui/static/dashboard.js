/**
 * Multiy Pro 旗舰版核心逻辑控制中心 - 深度增强旗舰版
 */
function multix() {
    return {
        // --- [ 1. 基础响应式状态 ] ---
        lang: localStorage.getItem('m_lang') || 'zh', // 语言持久化
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false, 
        searchQuery: '',
        
        // --- [ 国际化语言包 ] ---
        i18n: {
            zh: { 
                login: "登录", logout: "注销", guest: "访客身份", identity: "身份状态", 
                control: "管理中心", nodes: "集群节点", sys: "主控状态", 
                search: "搜索节点名称、IP或别名...", total: "总计", online: "在线",
                unlock: "解除管理限制", back: "返回访客模式", virtual: "演示节点"
            },
            en: { 
                login: "Login", logout: "Logout", guest: "Guest Mode", identity: "Identity", 
                control: "Control Center", nodes: "Cluster Nodes", sys: "Master Status", 
                search: "Search by Name, IP or Alias...", total: "Total", online: "Online",
                unlock: "Unlock Console", back: "Back to Guest", virtual: "Demo Node"
            }
        },
        t(key) { return this.i18n[this.lang][key] || key; },
        switchLang() { 
            this.lang = this.lang === 'zh' ? 'en' : 'zh'; 
            localStorage.setItem('m_lang', this.lang); 
        },

        // --- [ 2. 数据容器 ] ---
        // 赋予初始值防止 0% 闪烁
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

        // --- [ 6. 初始化核心 ] ---
        async init() {
            console.log("Multiy Engine Initializing...");
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
            }
            // 立即同步并开启心跳
            await this.fetchState();
            setInterval(() => this.fetchState(), 5000); 
        },

        // --- [ 7. 核心数据同步 ] ---
        async fetchState() {
            try {
                // 增加随机参数，强制绕过浏览器缓存
                const res = await fetch(`/api/state?v=${Date.now()}`);
                if (!res.ok) throw new Error("Backend Offline");
                const data = await res.json();
                
                // 核心赋值，确保数据对象完整性
                this.master = data.master || this.master;
                this.agents = data.agents || {};
                this.config = data.config || this.config;
                
                // 自动同步管理表单默认值
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

        get filteredAgents() {
            let list = Object.entries(this.agents);
            // 场景 A: 空列表自动注入虚拟小鸡占位
            if (list.length === 0) {
                return {
                    "virtual-001": {
                        hostname: "PRO-NODE-DEMO",
                        alias: this.t('virtual'),
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
                // 访客模式下物理隐藏标记为 hidden 的节点
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
            } catch (e) { alert("Operation Failed"); }
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 9. 超级订阅与导出 ] ---
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
            navigator.clipboard.writeText(text).then(() => alert(this.lang === 'zh' ? "已复制到剪贴板" : "Copied to clipboard"));
        },

        // --- [ 10. 认证管理：解决点击不响应关键 ] ---
        async login() {
            if (!this.loginForm.user || !this.loginForm.pass) {
                alert(this.lang === 'zh' ? "请完整输入账号密码" : "Please enter credentials");
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
                    // 登录后强制刷新页面以同步全局组件状态
                    window.location.reload(); 
                } else { 
                    alert(this.lang === 'zh' ? "凭据认证失败" : "Auth Failed"); 
                }
            } catch (e) { 
                alert("Server Connection Error"); 
            }
        },

        logout() {
            if (confirm(this.lang === 'zh' ? "确定注销登录？" : "Logout?")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        }
    }
}
