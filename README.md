# 🎮 Minestrator-Restart
[Minestrator](https://minestrator.com) 提供免费的 Minecraft 服务器托管，但每 4 小时会强制关机一次。本项目通过定时自动重启，绕过这一限制，实现服务器持续保活。
## 🔐 Secrets 配置
**Settings → Secrets and variables → Actions → New repository secret** 添加以下变量：
| Secret 名 | 必填 | 说明 | 示例 |
|---|---|---|---|
| `MINESTRATOR_ACCOUNT` | ✅ 必填 | 🧾 Minestrator 登录邮箱和密码，用英文逗号分隔 | `myemail@example.com,mypassword` |
| `MINESTRATOR_SERVER_ID` | ✅ 必填 | 🖥️ 服务器 ID | `123456` |
| `MINESTRATOR_AUTH` | ✅ 必填 | 🔑 API 授权 Token，含 Bearer 前缀 | `Bearer xxxxxxxxxxxxxxxx` |
| `GOST_PROXY` | ✅ 必填 | 🌐 Gost 代理地址，GitHub Actions IP 可能被识别为 VPN 导致登录失败，必须填写 | `socks5://user:pass@1.2.3.4:1080` |
| `TG_BOT` | ⬜ 可选 | 📨 Telegram 推送，Chat ID 和 Bot Token 用英文逗号分隔 | `987654321,123456:AAFxxx` |
## 🕐 执行时间
每天北京时间 **09:00 / 13:00 / 17:00 / 21:00** 自动触发，也可在 Actions 页面手动执行。
