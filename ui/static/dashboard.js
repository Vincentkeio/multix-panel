/**
 * MULTIX PRO - 核心前端逻辑 V145.0
 * 优化点：实时凭据同步、HTTP 环境兼容性复制、自动登录持久化
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST', token: '', ip4: '', ip6: '' }, 
        
        // 界面控制
        drawer: false, 
        adminModal: false, 
        isRefreshing: false,
        isLoggedIn: false, 
        showLoginModal: false,
        
        // 交互与临时变量
        curSid: '', 
        curNode: {}, 
        editingSid: null,
        tempUser: '', 
        tempPass: '', 
        tempToken: '', 
        tempAlias: '',
        loginUser: '', 
        loginPass: '',

        // --- [ 2. 初始化 ] ---
        async init() {
            // 检查本地存储恢复登录态
            const savedToken = localStorage.getItem('multiy_token');
            if (savedToken) {
                this.isLoggedIn = true;
            }
            
            await this.fetchState();
            // 每 3 秒同步一次集群数据
            setInterval(() => this.fetchState(), 3000);
        },

        // --- [ 3. 数据同步 ] ---
        async fetchState() {
            try {
                const r = await fetch('/api/state');
                if (!r.ok) throw new Error("API Offline");
                const d = await r.json();
                
                this.agents = d.agents || {};
                this.master = d.master || {};
                // 确保后端传回的 config 包含 ip4/ip6/token
                this.config = d.config || { user: 'ADMIN', token: '' };
                
                if (this.drawer && this.curSid) {
                    this.curNode = this.agents[this.curSid];
                }
            } catch(e) { 
                console.error("数据链路异常:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 4. 登录验证 ] ---
        async doLogin() {
            if (!this.loginUser || !this.loginPass) {
                alert("请输入完整的管理账号和密码");
                return;
            }

            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ 
                        user: this.loginUser, 
                        pass: this.loginPass 
                    })
                });

                const data = await res.json();

                if (res.ok && data.status === 'success') {
                    this.isLoggedIn = true;
                    this.config.user = data.user;
                    this.showLoginModal = false;
                    // 持久化 Token 用于后续鉴权
                    localStorage.setItem('multiy_token', data.token);
                    
                    this.loginUser = '';
                    this.loginPass = '';
                    
                    await this.fetchState();
                } else {
                    alert("登录失败: " + (data.msg || "凭据不正确"));
                    this.loginPass = '';
                }
            } catch (err) {
                alert("网络连接失败，请检查连通性");
            }
        },

        // --- [ 5. 管理功能 ] ---
        
        // 修改凭据核心逻辑 (增加实时刷新反馈)
        async confirmUpdateAdmin() {
            if (!this.tempUser) return alert("用户名不能为空");
            
            const token = localStorage.getItem('multiy_token');
            const updateData = { 
                user: this.tempUser, 
                pass: this.tempPass || null,
                token: this.tempToken || null 
            };

            const res = await fetch('/api/update_admin', {
                method: 'POST', 
                headers: { 
                    'Content-Type': 'application/json',
                    'Authorization': token 
                },
                body: JSON.stringify(updateData)
            });
            
            if (res.ok) { 
                // --- 实时更新 UI 状态，无需等待下次刷新 ---
                if (updateData.user) this.config.user = updateData.user;
                if (updateData.token) {
                    this.config.token = updateData.token;
                    localStorage.setItem('multiy_token', updateData.token);
                }

                alert("✅ 安全凭据更新成功！\n数据已实时同步至全局。");
                this.adminModal = false; 
                await this.fetchState(); 
            } else {
                const err = await res.json();
                alert("更新失败: " + (err.msg || "权限不足"));
            }
        },

        // --- [ 6. 复制功能 (含 HTTP 兼容性补丁) ] ---
        copyToClipboard(text) {
            if (!text) return;
            
            // 方案 A: 现代 HTTPS 环境接口
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(text).then(() => {
                    alert("Token 已成功复制到剪贴板");
                }).catch(() => {
                    this.fallbackCopy(text);
                });
            } else {
                // 方案 B: 传统 HTTP 环境兼容方案
                this.fallbackCopy(text);
            }
        },

        fallbackCopy(text) {
            const textArea = document.createElement("textarea");
            textArea.value = text;
            textArea.style.position = "fixed";
            textArea.style.left = "-9999px";
            textArea.style.top = "0";
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            try {
                document.execCommand('copy');
                alert("Token 已复制 (兼容模式)");
            } catch (err) {
                alert("当前浏览器不支持自动复制");
            }
            document.body.removeChild(textArea);
        },

        logout() {
            if (confirm("确定要退出并锁定控制台吗？")) {
                localStorage.removeItem('multiy_token');
                this.isLoggedIn = false;
                window.location.reload();
            }
        },

        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0))
            );
        },

        openDrawer(sid) {
            if (!this.isLoggedIn) {
                this.showLoginModal = true;
                return;
            }
            this.curSid = sid;
            this.curNode = this.agents[sid];
            this.drawer = true;
        },

        async addVirtualNode() {
            const res = await fetch('/api/manage_agent', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Authorization': localStorage.getItem('multiy_token')
                },
                body: JSON.stringify({ action: 'add_demo' })
            });
            if(res.ok) await this.fetchState();
        }
    }
}
