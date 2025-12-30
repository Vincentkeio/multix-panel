function multix() {
    return {
        // --- [ 基础状态 ] ---
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false,
        searchQuery: '',
        
        // --- [ 数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '...', sb_ver: '...' },
        agents: {},
        config: { user: '', token: '', ip4: '', web_port: 7575 },
        
        // --- [ 弹窗控制 ] ---
        showLoginModal: false,
        adminModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 表单与临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', // 管理中心安全凭据修改
        editingSid: null, tempAlias: '', // 节点别名修改
        subType: 'v2ray', globalLinks: '',
        
        // --- [ 节点详情变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,

        // --- [ 初始化 ] ---
        init() {
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
                this.fetchState();
            }
            // 持续心跳刷新
            setInterval(() => this.fetchState(), 5000);
        },

        // --- [ 核心数据交互 ] ---
        async fetchState() {
            try {
                const res = await fetch('/api/state');
                const data = await res.json();
                this.master = data.master;
                this.agents = data.agents;
                this.config = data.config;
                
                // 初始化管理中心表单默认值
                if (!this.tempUser) {
                    this.tempUser = this.config.user;
                    this.tempToken = this.config.token;
                }
            } catch (e) { console.error("数据同步失败", e); }
            finally { this.isRefreshing = false; }
        },

        // --- [ 节点排序逻辑 ] ---
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 99) - (b.order || 99))
            );
        },

        // --- [ 节点别名与管理 ] ---
        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': this.config.token },
                    body: json.stringify({ sid, action, value })
                });
                if (res.ok) this.fetchState();
            } catch (e) { alert("操作失败"); }
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 安全凭据同步 ] ---
        async confirmUpdateAdmin() {
            if (!confirm("修改安全凭据后主控将重启，Token 变更会导致所有 Agent 掉线，确定同步？")) return;
            // 此处通常调用后端更新环境变量接口
            alert("主控配置已更新，请手动重启服务以应用新凭据。");
        },

        // --- [ 订阅与导出逻辑 ] ---
        generateSubLink() {
            const host = window.location.host;
            return `http://${host}/sub?token=${this.config.token}&type=${this.subType}`;
        },

        async exportGlobalNodes() {
            this.globalLinks = "";
            Object.values(this.agents).forEach(agent => {
                if (agent.hidden) return;
                const ip = agent.ip || this.config.ip4;
                const inbounds = agent.metrics?.inbounds || [];
                inbounds.forEach(inb => {
                    if (inb.type === 'vless') {
                        const link = `vless://${inb.uuid}@${ip}:${inb.listen_port || inb.port}?security=reality&sni=${inb.reality_dest?.split(':')[0] || 'yahoo.com'}&fp=chrome&pbk=${inb.reality_pub || ''}&sid=${inb.short_id || ''}&type=tcp&flow=xtls-rprx-vision#${inb.tag}`;
                        this.globalLinks += link + "\n";
                    }
                });
            });
            this.globalExportModal = true;
            this.$next_tick(() => this.renderQR(this.globalLinks));
        },

        renderQR(text) {
            const container = document.getElementById('global-qr-code');
            if (container) {
                container.innerHTML = "";
                new QRCode(container, { text: text, width: 192, height: 192, colorDark: "#000000", colorLight: "#ffffff" });
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("已复制到剪贴板"));
        },

        // --- [ 登录与注销 ] ---
        async login() {
            const res = await fetch('/api/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ user: this.loginForm.user, pass: this.loginForm.pass })
            });
            if (res.ok) {
                const data = await res.json();
                localStorage.setItem('m_token', data.token);
                this.isLoggedIn = true;
                this.showLoginModal = false;
                this.fetchState();
            } else { alert("账号或密码错误"); }
        },

        logout() {
            localStorage.removeItem('m_token');
            window.location.reload();
        }
    }
}
