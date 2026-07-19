# vps-gateway — 便携 frps 安装包

把任意一台新 VPS 变成 personal-gateway 的**纯中继**：只跑 frps，无 Docker、无 nginx、无鉴权逻辑（所有 bearer token 校验都在 pz-win 的应用内部完成）。

## 适用场景

VPS 是临时的 / 要换新 VPS 时，在新机器上几分钟内重建整个入口。

## 使用（VPS 上，root）

```bash
# 1. 把这个目录拷到 VPS
scp -r vps-gateway root@<vps>:/root/

# 2. 配置
cd /root/vps-gateway
cp gateway.env.example gateway.env
vim gateway.env        # FRP_TOKEN 必须与 pz-win 上 frpc 的 token 一致

# 3. 安装（幂等，可重复跑）
./install.sh
```

国内 VPS 访问 GitHub 慢/不通时：提前在别的机器下载
`frp_<version>_linux_<arch>.tar.gz` 放到本目录（或 `gateway.env` 里设 `FRP_TARBALL`），
`install.sh` 会直接用本地包，不走网络。

## 云安全组需要开的端口

| 端口 | 用途 |
|------|------|
| `FRP_BIND_PORT`（默认 7000） | frp 控制通道，pz-win 的 frpc 连这里 |
| `PUBLIC_PORT`（默认 300） | personal gateway 公网入口（所有个人 MCP 都走它） |
| 7001 | mouding MCP（若此 VPS 也承载 mouding） |

**不要**对外开放 7500 —— dashboard 只监听 127.0.0.1，用 SSH 隧道访问：

```bash
ssh -L 7500:127.0.0.1:7500 root@<vps>   # 然后浏览器开 http://127.0.0.1:7500
```

## 架构

```
client → http://<vps>:300/<service>/...        (公网, 只有这一个入口)
            │  frps (本安装包, 纯转发)
            ▼
         frpc on pz-win (Docker) → nginx → gemini-search / mimo-tts
                                             ↑ bearer token 在这里校验

mouding MCP → <vps>:7001  （独立的原生 frpc，半生产，与上面完全分离）
```
