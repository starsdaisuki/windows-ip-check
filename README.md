# Windows IP Check

在 Windows 原生检查 IPv4 出口、IP 归属和可用的风险标记。无需 WSL、Docker、管理员权限或额外安装。

## 一条命令

保持 Clash **TUN 模式**开启，在 **PowerShell** 中粘贴：

```powershell
irm -Headers @{Accept='application/vnd.github.raw+json'} https://api.github.com/repos/starsdaisuki/windows-ip-check/contents/ipquality.ps1 | iex
```

支持 Windows PowerShell 5.1 和 PowerShell 7，需要系统自带的 `curl.exe`（Windows 10 1803+）。
此命令会下载并执行仓库中的脚本；源码就是 [ipquality.ps1](ipquality.ps1)。

先看 `Verified IP` 是否为你想测的节点出口。两个出口查询一致，只说明这些请求的出口一致，
不能证明所有网站都走了同一个节点。TUN 的实际覆盖取决于客户端规则。

## 只有系统代理，或需要指定端口

默认使用原生 Windows 路由，忽略 curl 配置和代理环境变量，**不会自动读取 Windows 系统代理**。
可显式指定 Clash 的实际混合端口；下面 `7897` 是示例：

```powershell
& ([scriptblock]::Create((irm -Headers @{Accept='application/vnd.github.raw+json'} https://api.github.com/repos/starsdaisuki/windows-ip-check/contents/ipquality.ps1))) -Proxy http://127.0.0.1:7897
```

指定的代理连接失败时会停止，不自动回落直连。

## 检查什么

| 来源 | 首版可获取的信息 |
|---|---|
| IPinfo demo | 国家、ASN、ISP/机房类型，以及接口返回的 VPN/代理/Tor/relay/hosting 标记 |
| ipapi.is 免费 API | 归属信息；只有接口实际返回风险字段时才展示 |
| DB-IP 免费 API | 归属信息 |

这不是 xykt IPQuality 的完整移植。首版没有八库全覆盖、流媒体解锁、DNSBL、SMTP 或 IPv6。
三个查询也不等于三家完整风险评分：目前 ipapi.is 免费响应通常不含风险字段。

- `INFO`：返回了可用信息，不表示综合质量优秀。
- `PROBE-FAIL`：请求或解析失败，不等于 IP 被封。
- `UNKNOWN / NOT PROVIDED`：没有数据，不能当成“否”或低风险。
- `COMPLETE`：三项已配置的归属查询均成功，不表示所有风险字段齐全。
- `EGRESS-UNVERIFIED` / `EGRESS-CHANGED-OR-UNVERIFIED`：出口核对失败，本轮不能作为稳定出口的质量结论。

检测前后分别向 ipify 和 Cloudflare 查询出口，要求一致；查库时显式指定该 IP。
不生成或上传在线报告。第三方 API 仍会收到被查询的 IP。单库信息不代表所有网站的判断。

## 本地文件与参数

下载 `ipquality.ps1` 后，在文件所在目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ipquality.ps1
```

执行策略参数只适用于这个子进程，不修改系统设置。

| 参数 | 用途 |
|---|---|
| `-CheckExitOnly` | 只做两个出口查询，不查 IP 数据库 |
| `-ExpectedIP` | 填已知的目标节点公网 IPv4；不一致则在查库前停止 |
| `-Proxy` | 显式 HTTP/HTTPS/SOCKS 代理 URL；HTTP CONNECT 已实测 |
| `-Json` | 输出结构化报告 |
| `-TimeoutSec` | 每次请求超时秒数，默认 10，范围 2–30 |

文件模式退出码：0 为完成（可能部分来源失败），2 为出口异常，3 为所有数据库失败。
JSON 中同时查看 `status` 与 `risk_available`；不能只看退出码判定质量。
一行下载模式运行结束后保留当前终端。

## 验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\ipquality.tests.ps1
```

15 项离线测试使用合成响应，涵盖缺失字段、假 IP、出口变化、接口失效等情况。
已在原生 Windows PowerShell 5.1 实测三源查询、HTTP CONNECT 代理、不可用代理、
错误预期出口，以及下载执行后终端保持运行。实际 TUN 规则需由使用者核对。

MIT License。代码从 StarUnlock 的原生 Windows 检测器独立发布；没有复制 xykt 的 Bash 实现。
