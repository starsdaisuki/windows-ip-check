# Windows IPQuality

在 Windows 上运行 **xykt/IPQuality 原版完整报告**：IP 类型、多库风险评分、代理/VPN/机房/滥用标记、流媒体及 AI 解锁、邮局与 400+ 黑名单检查。

## 换一台电脑也只用这一条

开启 Clash **TUN 模式**，打开 **PowerShell**，粘贴：

```powershell
irm https://raw.githubusercontent.com/starsdaisuki/windows-ip-check/v2/ipquality.ps1 | iex
```

适用于 64 位 Windows 10/11、Windows PowerShell 5.1 或 PowerShell 7。无需预装 Git、Bash、jq、WSL 或 Docker。

**第一次**自动下载并准备 Cygwin 原生 Windows 工具，下载约 70 MB，通常需要几分钟；后续复用缓存。无需管理员权限，不添加系统 PATH、桌面快捷方式或安装目录注册表记录。缓存位于 `%LOCALAPPDATA%\WindowsIPCheck`。

脚本使用 Windows 网络栈。运行前会比较 Windows curl 与原生 Bash curl 的出口；不一致就停止。仍需核对显示的 IP 是否为所选 Clash 节点，TUN 的实际规则由客户端决定。

## 就是原报告，没有删检测项目

启动器下载并校验原作者的 `ip.sh`，**不修改其代码和检测规则**。当前校验版本为 `v2026-09-04`，上游提交 `3c0eb8856c67ad351020d1edd1bfd4e2515d32fe`。

默认相当于在原生 Windows Bash 中执行：

```bash
bash ip.sh -4 -n -p
```

- `-4`：检查 IPv4。
- `-n`：依赖已经自动准备，只跳过原脚本的 Linux 包管理器安装检查。
- `-p`：保留完整报告，关闭在线报告上传。
- 同时保存完整 JSON 到缓存中的 `reports` 目录，运行结束会打印路径。

原版包含 IPinfo、ipregistry、ipapi、IP2Location、AbuseIPDB、Scamalytics、IPQS、ipdata、DB-IP 的对应检测项。某库返回不了数据时，不代表低风险，也不保证所有库每次都能返回。

**上游接口限制：** 如果多库中转站返回 Cloudflare 拒绝页，原版会自动进入 **Lite**，跳过部分库。这时启动器明确打印 `UPSTREAM LIMITED (Lite)`，不能视为完整纯净度报告。报告后的汇总还会列出实际获得的评分源数量。

**SMTP 限制：** 原脚本尝试绑定出口公网 IP；TUN/NAT 下该地址通常不是本机接口地址，因此邮局结果不能直接当成 IP 信誉结论。DNSBL 的策略类标记也不等于滥用黑名单。这里保留原版语义，不编造替代评分。

## 可选：英文或 IPv6

下载 `ipquality.ps1` 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ipquality.ps1 -English
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ipquality.ps1 -IPv6
```

执行策略参数只作用于当前子进程，不修改系统设置。

## 实现与许可

本仓库是 **Windows 自动准备环境和启动器**，不再使用早期三源简化查询器。

- [xykt/IPQuality](https://github.com/xykt/IPQuality)：原检测脚本，AGPL-3.0，由启动器从原仓库下载。
- [Cygwin](https://cygwin.com/)：官方原生 Windows 运行工具；setup 校验签名索引和软件包哈希。
- 本仓启动器：MIT。没有将上游脚本或运行时二进制重新打包进本仓库。
- 唯一系统命令适配是把上游用于查看 TCP 25 端口的 `ss` 调用交给 Windows `netstat`；IPQuality 的报告生成和评分规则不变。

依赖和脚本下载需要网络；第三方检测服务会收到查询请求。默认不上传在线报告。

## 测试

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\ipquality.tests.ps1
```

测试默认完整模式、上游固定版本、出口核对、参数验证和报告路径边界。完整功能另以真实 Windows 上生成的原版报告验收。
