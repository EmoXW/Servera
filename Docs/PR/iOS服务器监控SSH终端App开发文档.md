# iOS 服务器与 NAS 管理 App 开发文档草案

> 版本：0.2  
> 日期：2026-05-29  
> 阶段：产品与技术方向草案 + 当前实现边界修订

## 1. 项目概述

本项目计划开发一款原生 iOS App，核心能力是让用户在手机上管理自己的 Linux / macOS 服务器和群晖 NAS。普通服务器主要通过 SSH 获取状态、打开终端、查看 Docker 与系统资源；群晖 NAS 主要通过 DSM Web API 登录，查看系统状态、资源监控、存储空间、文件、下载和常用控制入口。

产品方向参考 ServerCat、SwiftServer 与派派助手，但定位为我们自己的轻量、私密、直观的个人服务器/NAS 管理工具。首版重点不做复杂运维平台，而是把“添加设备、看到关键状态、进入终端或文件、完成常用管理”这条主路径打磨顺畅。

## 2. 参考产品观察

### ServerCat

App Store 页面展示的核心方向包括：

- SSH 连接后的服务器状态监控。
- SSH 密钥管理。
- CPU 每核心使用率、GPU 状态、内存、网络、磁盘读写、Docker 容器状态。
- SSH 终端、终端主题、命令片段、批量命令执行。
- 数据强调本地与个人 iCloud 存储，不上传到第三方服务器。

参考链接：https://apps.apple.com/jp/app/servercat-ssh-terminal/id1501532023

### SwiftServer

App Store 页面展示的核心方向包括：

- iOS / iPadOS / macOS 上实时监控和管理服务器。
- CPU、GPU、内存、Docker、网络、存储分区、IP 位置。
- SSH 终端、SFTP 文件管理、iCloud 同步、终端字体/颜色/背景自定义。
- 新版本提到 Jump Server、全球视图、小组件、实时活动、服务器标签筛选、自定义状态页编排、服务器之间 SFTP 传输。

参考链接：https://apps.apple.com/cn/app/swiftserver-%E6%9C%8D%E5%8A%A1%E5%99%A8%E7%9B%91%E6%8E%A7-ssh%E7%BB%88%E7%AB%AF/id6740036221

### Traversio

Traversio 不是直接面向用户的服务器监控 App，而是面向 Apple 平台的原生 Swift SSH / SFTP 客户端库。它的设计对本项目的底层连接层很有参考价值：

- 使用 async/await 暴露 SSH 连接、命令执行、Shell、SFTP 等能力。
- 支持 Host Key Trust、密码认证、键盘交互认证、公钥认证。
- 支持 Exec、流式 Exec、PTY Shell、SFTP、SCP、端口转发、ProxyJump、SOCKS5 / HTTP CONNECT 代理。
- 提供结构化诊断日志、连接状态事件、延迟快照和 SSH 端口延迟测量。
- 文档明确说明凭据存储、信任存储持久化、重连策略、会话恢复、大输出保留策略仍应由应用层负责。
- 需要重点确认开源/商业授权边界，避免后续闭源 App 分发时出现许可风险。

参考链接：https://traversio.org

### 派派助手

派派助手是面向群晖 NAS 的手机管理工具，对本项目的 NAS 模块有参考价值：

- 通过 DSM 地址、IP 或 QuickConnect ID 登录。
- 支持 http / https 协议和 5000 / 5001 等 DSM 端口。
- 控制台查看系统状态、产品型号、系统名称、散热状态、运行时间。
- 资源监控查看 CPU、内存、网络和磁盘。
- 文件页浏览 File Station 文件并做基本操作。
- 下载页查看从 File Station 下载的文件。
- 设置页提供关机、重启、SSH 开关、主题、终端、相册备份等常用入口。
- 版本记录中提到对 Container Manager、Synology Photos、任务计划、后台任务、外接设备等群晖生态功能的支持。

参考链接：https://apps.apple.com/cn/app/%E6%B4%BE%E6%B4%BE%E5%8A%A9%E6%89%8B-%E6%8E%8C%E4%B8%8A%E4%BA%91%E7%9B%98/id1548424168

## 3. 产品定位

### 目标用户

- 有一台或多台 VPS / 云服务器 / 家庭服务器的个人开发者。
- 有群晖 NAS，希望用一个 App 查看 NAS 状态、浏览文件、管理下载和执行常用控制的人。
- 需要在手机上临时排查服务状态的站长、运维、独立开发者。
- 使用 Docker 部署服务，希望快速查看容器状态的人。

### 核心价值

- 同时支持两类常见个人设备：SSH 服务器与群晖 NAS。
- 普通服务器不需要安装 Agent，直接通过 SSH 获取状态。
- 群晖 NAS 不强依赖 SSH，优先通过 DSM Web API 获取状态和文件能力。
- 私密优先，服务器账号、密钥、DSM 账号、会话信息和监控数据默认只保存在本机 Keychain / 本地数据库。
- 首页快速判断“哪些设备在线、压力是否异常、存储是否紧张、是否有容器异常”。
- 需要操作时可以直接进入 SSH 终端、DSM 文件管理或 NAS 控制入口。
- 用户可以把 App 调成自己的工作台：应用主题、终端主题、仪表板卡片、状态页布局都可以个性化。

### 首版产品原则

- 先把单设备监控体验做好，再扩展批量管理。
- Linux 服务器数据采集命令尽量兼容常见发行版。
- 群晖 NAS 优先走公开或稳定的 DSM Web API，不能稳定调用的能力先不放进 MVP。
- 自定义能力要从首版就预留数据结构，避免后续改 UI 时迁移困难。
- 任何敏感数据默认不上传。
- 后续付费点可以围绕高级终端、SFTP、DSM 文件高级操作、相册备份、iCloud 同步、小组件、批量命令、告警等展开。

## 4. MVP 功能范围

### 4.1 连接对象管理

设备栏用于新增、编辑和管理连接对象。用户添加指定设备后，App 根据设备类型和能力自动分发：

- SSH 服务器：连接成功后显示在仪表盘；如果扫描到 Docker，会员用户的 Docker 栏自动出现该服务器卡片。
- 群晖 NAS：连接成功后显示在 NAS 栏，同时也可以在仪表盘显示摘要卡片。
- 未连接成功的设备：保留在设备栏草稿/失败状态，不进入仪表盘主列表。

- 新增 SSH 服务器：
  - 名称
  - 设备备注。
  - 主机地址：IP 或域名
  - 端口，默认 22
  - 用户名
  - 认证方式：密码 / 私钥
  - 私钥 passphrase，可选
  - 是否在首页展示
  - 标签，可选，首版可先预留字段
- 新增群晖 NAS：
  - 名称 / 备注
  - 协议：http / https
  - 地址：IP / 域名 / QuickConnect ID
  - 端口：http 默认 5000，https 默认 5001
  - DSM 账号
  - DSM 密码
  - 是否记住密码
  - 是否自动登录
  - 是否验证 SSL 证书
  - 是否在首页展示
  - NAS 配置界面不要出现 SSH 快速粘贴、SSH 文案或 22 端口默认值。
  - 协议建议放在地址输入前方或同一行，地址输入框只接收主机、域名或 QuickConnect ID，避免用户重复输入 `http://`。
  - 切换协议时自动联动默认端口：选择 http 自动填 5000，选择 https 自动填 5001；后续可识别用户自定义端口并保留。
- 编辑连接对象。
- 删除连接对象。
- 测试连接。
- 显示最近连接时间、连接状态、延迟。
- 连接成功反馈：
  - 显示成功动画，例如卡片点亮、连接线闭合、状态环完成。
  - 自动进入对应详情页或回到对应 Tab，首版可让用户选择。
  - 仪表盘/NAS/Docker 自动刷新。
- 连接失败反馈：
  - 弹窗给出明确原因和下一步。
  - 常见错误包括：主机不可达、端口未开放、连接超时、账号不存在、密码错误、私钥错误、Host Key 变化、权限不足、DSM SSL 证书错误、DSM API 不可用。
  - 弹窗提供操作：重试、编辑配置、查看诊断。

### 4.2 Dashboard 首页

仪表盘展示用户已经成功连接的设备，是 App 的主界面。服务器和 NAS 都可以在这里出现，但展示重点是“当前设备是否正常、是否需要关注”。

- 总设备数、在线数、离线数。
- 搜索设备。
- 异常优先区域：离线、负载高、磁盘快满、Docker 异常。
- SSH 服务器卡片：
  - 名称、系统图标或系统名称
  - 在线状态、延迟
  - CPU 核心数
  - 内存总量
  - 磁盘总量
  - 运行时间
  - 柔光健康仪表，花瓣分别代表 CPU、内存、存储、网络、Docker。
  - 网络上传/下载速率
  - 磁盘读写速率
  - 精美卡片动效：在线呼吸点、花瓣轻微浮动、网络水流线、数字滚动。
- 群晖 NAS 卡片：
  - 名称、型号、DSM 版本
  - 在线状态、连接方式
  - 运行时间
  - 温度 / 散热状态
  - CPU、内存、网络摘要
  - 存储空间使用率和健康状态
  - NAS 存储抽屉，多个 Volume 像柔和磁盘槽一样展示。
  - 快捷入口：控制台、文件、下载、设置
- 卡片排序：
  - 用户可以长按拖拽设备卡片进行排序。
  - 排序结果本地保存，后续可通过 iCloud 同步。
  - 异常设备可以临时置顶，但不覆盖用户手动排序。
  - 支持固定主设备，固定设备显示为更大的主卡。
- 点击卡片：
  - 点击 SSH 服务器卡进入服务器详情页。
  - 点击 NAS 卡进入 NAS 详情页。
  - 卡片/花瓣进入详情页可使用 `matchedGeometryEffect` 做展开动效。

### 4.2.1 NAS Tab

NAS 栏专门展示用户添加并连接成功的群晖 NAS。NAS 作为免费附加宣传点，功能不需要覆盖完整 DSM，但要把状态展示做精致。

- NAS 卡片能力参照仪表盘：
  - 名称 / 备注。
  - 型号。
  - DSM 版本。
  - 在线状态。
  - 温度/散热状态。
  - CPU / 内存 / 网络摘要。
  - 存储空间健康。
  - Docker 容器基础状态。
- 支持 NAS 卡片排序。
- 点击 NAS 卡进入 NAS 详情页。
- 可以提供快捷操作：
  - 打开文件。
  - 查看存储。
  - 查看 Docker。
  - 重启/关机，必须二次确认。

### 4.2.2 Docker Tab

Docker 栏只显示 SSH Server Docker，不混入 NAS Docker。添加 SSH 服务器并扫描到 Docker 后，系统自动把该服务器加入 Docker 栏；NAS Docker 继续只在 NAS 栏展示和管理。

- Docker 首页定位：
  - 首页是“服务器 Docker 入口列表”，不是容器列表。
  - 顶部展示轻量总览：Docker 服务器数、运行容器数、总容器数、停止/异常数。
  - 每台服务器只占一行，展示服务器名称、IP/系统摘要、运行容器数、总容器数、状态点和右侧箭头。
  - 首页不展开容器行，也不显示“查看全部 N 个容器”，避免占用首屏。
- 二级容器管理：
  - 点击服务器入口进入 `容器管理` 二级页。
  - 二级页展示完整容器列表：容器名、镜像、运行/停止状态、CPU、内存、运行时间。
  - 点击容器进入容器详情页。
  - 容器详情支持真实 SSH Docker 操作：启动、停止、重启、刷新、日志。
  - 操作后必须读回服务器状态并刷新 UI，不能只因为命令返回成功就假显示成功。
  - 日志窗口只显示 `docker logs` 内容，不混入 sudo 提示、命令 marker 或采集脚本输出。
- 权限与安全：
  - 普通 `docker` 权限不足时可用已保存 SSH 密码通过 stdin 做 sudo 只读/操作兜底，密码不能出现在命令字符串、日志和 UI。
  - 停止、重启等会影响服务的操作必须二次确认。
  - 操作失败要区分 Docker 不存在、权限不足、sudo 不可用、容器不存在、SSH 断开。
- 商业边界：
  - 当前开发阶段 Server Docker 操作入口先放开，方便真实验证。
  - 后续正式 Pro 边界单独收口；不影响 NAS Docker 免费能力。

### 4.3 服务器详情页

服务器详情页必须是完整页面跳转，不使用半屏抽屉。用户在仪表盘点击服务器卡片或花朵节点后，直接进入完整详情页；底部主 Tab 隐藏，只保留顶部返回按钮和更多操作入口。这样视觉上不会出现“页面只打开了一半”的割裂感，也更符合监控类页面的沉浸式阅读需求。

首屏设计目标是“进来就看到状态”，不要把进程、网络、存储都做成二级按钮。终端是明确操作入口，可以保留为按钮；进程、网络、存储、内存和 CPU 负载应该作为默认可见的信息卡片。

详情页按纵向信息流展示：

- 服务器概览：
  - 主机名
  - 操作系统与版本
  - 内核版本
  - 架构
  - Uptime
  - 公网 IP / 内网 IP
- CPU：
  - 顶部显示总使用率和温度。
  - 使用“核心活跃矩阵”或短柱点阵展示每核心状态，避免只有一根进度条。
  - User / System / Nice / IOWait / Steal 占比
  - Load Average 使用 1m / 5m / 15m 多线趋势图。
  - 温度，能获取则展示，获取不到隐藏
- 内存：
  - Total
  - Used
  - Cached / Buffers
  - Free
  - 使用环形结构图表达 Used / Cached / Free，Swap 使用情况用细进度条即可。
- 进程：
  - PID
  - Process
  - User
  - CPU%
  - Mem
  - 默认在详情页直接显示 Top 4-6，按 CPU 排序。
  - 后续版本再支持点击进程查看详情或发送信号。
- 网络：
  - 默认网卡
  - IP / CIDR
  - 实时上传/下载速率
  - 累计上传/下载流量
  - 使用上传/下载双色环或流线动画表达方向。
- 存储：
  - 挂载点
  - 文件系统类型
  - 已用 / 总量
  - 使用率可以保留进度条，但要搭配读写速度、IOPS、延迟小指标。
  - 读写速率
  - IOPS / 延迟，首版能采集则展示，采集不到可降级隐藏
- Docker：
  - Docker 是否安装
  - 正在运行容器数量
  - 容器名称
  - 状态
  - CPU%
  - 内存
  - 网络 I/O
  - Block I/O
  - 启动/停止/重启容器放到后续版本，首版只读更稳

视觉建议：

- 详情页不要照搬 ServerCat/SwiftServer 的黑色卡片堆叠，可以沿用 Servera 的柔光白粉底色，并给不同指标分配数据色：CPU 青蓝、负载暖黄、内存玫粉、网络蓝橙、存储淡绿、进程深粉。
- 卡片进入时使用轻微上浮和透明度动画；CPU 核心矩阵逐格点亮，负载曲线从左到右绘制，内存环形图从 0 扫到当前值。
- 第一屏优先显示身份卡、终端入口、CPU 核心矩阵和负载曲线；继续下滑立刻看到内存、进程、网络、存储，不需要再点四宫格入口。
- 终端入口用醒目的操作卡，不和进程/网络/存储混成同一组按钮。

### 4.4 SSH 终端

首版提供基础 SSH 终端：

- 打开服务器终端。
- 支持密码和私钥认证。
- 支持基本终端输入输出。
- 支持复制文本。
- 支持常用组合键辅助按钮：Ctrl、Esc、Tab、方向键。
- 终端主题首版可内置浅色/深色两套。

### 4.5 群晖 NAS 管理

首版群晖模块建议以“只读监控 + 文件基础浏览 + 安全控制”为主，避免一开始就覆盖全部 DSM 控制面板。

- DSM 登录：
  - 支持 http / https。
  - 默认 http 使用 5000，https 使用 5001，切换协议时联动端口。
  - 支持 IP / 域名。
  - QuickConnect ID 先作为待验证能力，优先保证 IP / 域名连接稳定。
  - 支持账号密码登录。
  - 支持记住密码和自动登录。
  - 支持 SSL 证书校验开关。
- NAS 控制台：
  - 产品型号。
  - 设备名称。
  - DSM 版本。
  - 运行时间。
  - 温度 / 散热状态。
  - CPU、内存、网络实时状态。
  - 存储空间列表：已用、可用、容量、状态。
- NAS 控制面板：
  - 首页/详情页使用精致纵向列表入口：左侧彩色图标，中间模块名与一行状态摘要，右侧箭头进入二级页。
  - 控制面板入口只保留：用户与群组、外部访问、网络、终端机、信息中心、更新还原。
  - 点击模块进入独立二级页面，不在页面顶部横向切模块。
  - 用户与群组页只展示清爽用户列表：正常/停用、用户名、当前账号/管理员标记、关键群组摘要。
  - 用户详情页只保留账号与密码、用户群组；修改账号名和密码必须弹高危确认。
  - 网络页展示网络设置和代理服务器，保存前必须确认，保存后以 DSM 读回状态为准。
  - 终端机页只保留 SSH 开关、Telnet 开关、SSH 端口，不展示 SNMP 和算法细节。
- File Station 文件：
  - 浏览共享文件夹。
  - 浏览目录。
  - 文件 / 文件夹名称、类型、大小、修改时间。
  - 预览常见图片、文本，其他格式交给系统分享面板。
  - 下载文件到 App 沙盒。
  - 上传、删除、重命名、移动、复制放到后续版本。
- 下载：
  - 展示 App 内下载任务。
  - 支持暂停、继续、失败重试，首版可先做本地下载任务。
  - DSM Download Station 集成放到后续版本。
- 设置/控制：
  - 退出登录。
  - 重新登录。
  - 打开 DSM 网页控制台。
  - 关机、重启、SSH 开关属于高风险操作，首版可先只做入口设计，正式执行放到后续版本并加二次确认。

### 4.6 设置

- Face ID / Touch ID 锁定 App。
- 默认刷新间隔。
- 单位设置：
  - 网络速率：B/s、KB/s、MB/s 自动格式化
  - 温度：摄氏 / 华氏后续可选
- 数据存储说明。
- 连接类型管理：SSH 服务器 / 群晖 NAS。
- 关于与隐私政策入口。

### 4.7 外观与自定义

自定义能力建议作为独立模块设计，不要只散落在设置项里。它会影响 Dashboard、服务器详情页、群晖控制台、终端、小组件和实时活动。

首版建议支持：

- 应用外观：
  - 跟随系统。
  - 亮色模式。
  - 暗色模式。
  - 主题色选择：紫、蓝、青、绿、黄、橙、红、粉等预设色。
  - App 图标选择，首版可先内置 3-5 个图标。
- 仪表板设置：
  - 是否显示延迟。
  - 延迟颜色开关。
  - 刷新间隔：例如 5 秒、10 秒、30 秒、60 秒。
  - 减少实时状态动画，降低资源占用。
  - 网络和磁盘 I/O 显示单位：自动 / 比特 / 字节。
- 状态详情布局：
  - 用户可调整服务器详情页卡片顺序。
  - 用户可隐藏不关心的卡片。
  - 默认卡片包括：头部、CPU 使用率、CPU 负载、内存、进程、网络、存储、IP 位置、Docker、GPU。
  - 群晖 NAS 可单独维护一套卡片：系统状态、资源监控、存储空间、文件入口、下载任务、套件状态。
  - 支持恢复默认布局。
- 终端主题：
  - 内置浅色、深色、高对比度主题。
  - 可配置字体、字号、光标样式、背景透明度。
  - 可配置 ANSI 色板，后续支持导入主题。
- 小组件与实时活动：
  - 选择展示设备。
  - 选择展示指标：在线状态、CPU、内存、存储、网络、容器异常。
  - 选择颜色风格：跟随应用主题 / 独立主题。

交互原则：

- 卡片排序采用长按拖动。
- 删除或隐藏卡片必须可恢复。
- 主题色应只影响强调色和图表色，不应该破坏状态颜色含义。
- 危险/警告状态颜色不能被主题完全覆盖。
- 自定义设置需要支持 iCloud 同步，但首版可以只本地保存。

## 5. 后续版本功能

### V1.1

- SFTP 文件浏览、上传、下载、删除、重命名。
- 群晖 File Station 上传、删除、重命名、移动、复制。
- 更完整的终端字体、字号、主题自定义。
- 状态详情布局编辑增强：添加卡片、隐藏卡片、恢复默认。
- 服务器标签筛选。
- 更完整的 Docker 管理：启动、停止、重启、查看日志。

### V1.2

- Jump Server / ProxyJump。
- 批量命令执行。
- 命令片段 Snippets。
- iCloud 私有数据库同步服务器配置。
- 群晖 Download Station。
- Synology Photos 基础相册浏览与备份。
- iPad 双栏布局。

### V2.0

- 小组件。
- Live Activities 实时状态。
- 自定义状态页卡片排序、小组件样式和实时活动样式。
- 告警规则：CPU、内存、磁盘、容器退出。
- 全球服务器视图。
- 多 NAS/多服务器统一告警中心。
- 多平台支持：iPadOS / macOS Catalyst 或原生 macOS。

## 6. 技术方案

### 6.1 客户端技术栈

- UI：SwiftUI。
- 架构：SwiftUI + Observation / MV 风格，必要时为复杂模块引入专用 Service。
- 本地数据库：SwiftData，存储服务器非敏感元数据、状态快照、用户偏好。
- 敏感信息：Keychain，存储密码、私钥、passphrase。
- SSH：优先评估 Traversio；备选方案为直接基于 SwiftNIO SSH 自建封装。
- 终端渲染：优先评估 SwiftTerm。
- 群晖：DSM Web API / File Station API，URLSession + Codable 封装。
- 图表：Swift Charts 或自定义 SwiftUI 图表。
- 并发：Swift Concurrency，SSH 会话与监控轮询使用 actor 隔离状态。
- 主题系统：AppTheme + DashboardLayout + TerminalTheme 三类配置，首版本地保存，后续进入 iCloud 同步；颜色 token 可参考 ColorTokensKit 的 OKLCH/LCH 设计方式。
- 动效系统：SwiftUI Animation、matchedGeometryEffect、contentTransition、symbolEffect、TimelineView、Canvas；动态渐变可参考/评估 ColorfulX；iOS 26+ 可探索 Liquid Glass，低版本使用 Material 兜底。

相关资料：

- Traversio：https://traversio.org
- SwiftNIO SSH：https://www.swift.org/blog/swiftnio-ssh/
- SwiftNIO SSH GitHub：https://github.com/apple/swift-nio-ssh
- SwiftTerm 文档：https://migueldeicaza.github.io/SwiftTerm/
- Synology DSM Login Web API Guide：https://kb.synology.com/en-my/DG/DSM_Login_Web_API_Guide/2
- Synology DSM Application Authentication：https://help.synology.com/developer-guide/integrate_dsm/web_authentication.html
- SwiftUI Animations：https://developer.apple.com/documentation/SwiftUI/Animations
- Apple Symbols Effects：https://developer.apple.com/documentation/symbols/
- ColorfulX：https://github.com/Lakr233/ColorfulX
- Colorful：https://github.com/Lakr233/Colorful
- ColorTokensKit-Swift：https://github.com/metasidd/ColorTokensKit-Swift

### 6.2 SSH 库选型建议

目前建议把 Traversio 放在第一优先级做技术验证，原因是它已经把很多 App 需要的 SSH 客户端能力做成较高层 API：

- `SSHClient.connect(...)` / `withConnection(...)` 适合短命令采集和长连接管理。
- `connection.execute(...)` 适合服务器指标采集命令。
- `openShell(...)` 适合接入 SwiftTerm 做 PTY 终端。
- SFTP API 可为后续文件管理功能节省大量底层工作。
- ProxyJump、连接代理、Keepalive、Timeout、Rekey、结构化日志都已经在 API 层有设计。
- 延迟能力可直接支持 Dashboard 里的连接耗时或 RTT 展示。

但 Traversio 也有需要提前确认的点：

- 授权：官网提到商业授权与 AGPL 义务，若 App 准备闭源或上架，需要在正式采用前确认商业授权成本和条款。
- Keychain：文档说明 Keychain 凭据加载不是强制内建能力，因此应用仍需要自己负责 Keychain 存储和注入认证数据。
- Host Trust：应用仍需要自己持久化首次信任的 Host Key，并设计 Host Key 变化时的用户确认流程。
- 重连：自动重连和会话恢复属于应用层职责。
- 终端渲染：Traversio 提供 PTY Shell 通道，不提供终端模拟器；终端 UI 仍需要 SwiftTerm 或同类组件。

备选方案是直接使用 SwiftNIO SSH。它的优势是 Apple 官方开源、Apache-2.0 许可、底层能力强；劣势是需要自己封装命令执行、Shell、SFTP、Host Trust、诊断、重连等大量应用层能力。除非 Traversio 授权或兼容性不合适，否则不建议首版直接从 SwiftNIO SSH 底层开始做。

### 6.3 分层结构建议

```text
App
├── Features
│   ├── Dashboard
│   ├── ServerDetail
│   ├── ServerEditor
│   ├── NASDashboard
│   ├── NASFiles
│   ├── NASDownloads
│   ├── Terminal
│   ├── Docker
│   ├── Resources
│   └── Settings
├── Domain
│   ├── Models
│   ├── Metrics
│   └── Commands
├── Services
│   ├── SSHClient
│   ├── MetricsCollector
│   ├── TerminalSession
│   ├── DockerService
│   ├── SynologyClient
│   ├── SynologyAuthStore
│   ├── FileTransferService
│   ├── KeychainStore
│   └── PersistenceStore
└── Shared
    ├── UIComponents
    ├── Formatters
    └── Utilities
```

### 6.4 数据采集策略

首版不安装 Agent，全部通过 SSH 执行系统命令采集。优点是部署简单，缺点是不同系统命令输出不完全一致，需要做兼容和降级。

建议采用“命令探测 + 解析器 + 降级展示”的方式：

1. 连接后检测系统类型。
2. 根据 Linux / macOS 选择不同命令集。
3. 每个指标独立采集，某个指标失败不影响整页。
4. 解析失败时隐藏对应字段，并记录调试日志。
5. 活跃详情页 3-5 秒刷新一次，首页 10-15 秒刷新一次。
6. App 进入后台后停止轮询，仅保留最后快照。

### 6.5 Linux 指标命令建议

系统信息：

```bash
uname -a
cat /etc/os-release
hostname
uptime -p
cat /proc/uptime
```

CPU：

```bash
nproc
lscpu
cat /proc/stat
cat /proc/loadavg
```

内存：

```bash
cat /proc/meminfo
free -b
```

磁盘：

```bash
df -PT -B1
lsblk -b -o NAME,MOUNTPOINT,FSTYPE,SIZE,TYPE
cat /proc/diskstats
```

网络：

```bash
ip -o addr show
cat /proc/net/dev
```

进程：

```bash
ps -eo pid,user,comm,pcpu,pmem,rss --sort=-pcpu | head -n 30
```

Docker：

```bash
docker version --format '{{json .}}'
docker ps -a --format '{{json .}}'
docker stats --no-stream --format '{{json .}}'
```

温度，尽力而为：

```bash
cat /sys/class/thermal/thermal_zone*/temp
sensors
```

### 6.6 macOS 指标命令建议

macOS 支持可放在第二阶段，先预留接口：

```bash
sw_vers
uname -a
sysctl -n hw.ncpu
sysctl -n hw.memsize
vm_stat
df -g
netstat -ib
top -l 1 -n 20
```

### 6.7 群晖 DSM API 方案

群晖模块应独立于 SSH 采集链路，避免把 NAS 功能硬塞进服务器监控模型。建议封装 `SynologyClient`，统一处理 DSM API 查询、登录态、错误码、SSL 策略和文件传输。

基础连接信息：

- http 默认端口：5000。
- https 默认端口：5001。
- DSM Web API 基础路径通常为 `/webapi/entry.cgi`。
- 旧版或部分接口可能使用 `/webapi/auth.cgi`，实际调用前应先通过 `SYNO.API.Info` 查询可用 API 的路径和版本。

建议登录流程：

1. 通过 `SYNO.API.Info` 查询 `SYNO.API.Auth`、`SYNO.Core.System`、`SYNO.FileStation.*` 等接口路径与版本。
2. 使用 `SYNO.API.Auth` 执行登录，保存 sid 或 cookie。
3. 登录成功后拉取系统信息，确认 DSM 版本与账号权限。
4. 后续请求统一附带 sid 或 cookie。
5. 退出账号时调用 `SYNO.API.Auth` logout，并清理本地会话。

示例接口形态：

```text
GET /webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth,SYNO.FileStation.List
GET /webapi/entry.cgi?api=SYNO.API.Auth&version=6&method=login&account=<account>&passwd=<password>&session=FileStation&format=sid
GET /webapi/entry.cgi?api=SYNO.Core.System&version=3&method=info
```

首版建议封装的能力：

- 认证：
  - 登录。
  - 登出。
  - 会话刷新/失效检测。
  - SSL 证书验证开关。
- 系统：
  - DSM 版本。
  - 产品型号。
  - 设备名称。
  - 运行时间。
  - 温度/散热状态，取不到则隐藏。
- 资源：
  - CPU。
  - 内存。
  - 网络。
  - 存储空间。
- File Station：
  - 查询共享文件夹。
  - 列目录。
  - 获取文件元数据。
  - 下载文件。
  - 基础预览。

注意事项：

- QuickConnect ID 可能涉及群晖自有中转/解析机制，首版先作为探索项，不作为强承诺；优先保证 IP、域名和反向代理地址稳定可用。
- DSM 6 / DSM 7 的 API 版本、路径和权限可能不同，必须先做 API Info 探测。
- 2FA、验证码、账户锁定、证书错误、反向代理路径、局域网/公网切换都要在错误模型中单独表达。
- 文件上传、移动、复制、解压、压缩、Photos、Container Manager、Download Station 等接口范围较大，建议拆到后续版本逐步加。

## 7. 核心数据模型草案

```swift
enum ManagedTargetKind {
    case sshServer
    case synologyNAS
}

struct ManagedTarget: Identifiable {
    var id: UUID
    var name: String
    var kind: ManagedTargetKind
    var tags: [String]
    var showOnDashboard: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct ServerProfile: Identifiable {
    var id: UUID
    var targetID: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var tags: [String]
    var showOnDashboard: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum AuthMethod {
    case password(keychainID: String)
    case privateKey(keychainID: String, passphraseKeychainID: String?)
}

struct SynologyProfile: Identifiable {
    var id: UUID
    var targetID: UUID
    var name: String
    var scheme: SynologyScheme
    var host: String
    var port: Int
    var account: String
    var passwordKeychainID: String?
    var verifySSLCertificate: Bool
    var autoLogin: Bool
    var showOnDashboard: Bool
}

enum SynologyScheme {
    case http
    case https
}

struct ServerSnapshot {
    var serverID: UUID
    var collectedAt: Date
    var connection: ConnectionState
    var system: SystemInfo?
    var cpu: CPUMetrics?
    var memory: MemoryMetrics?
    var disks: [DiskMetrics]
    var networks: [NetworkMetrics]
    var processes: [ProcessInfo]
    var docker: DockerMetrics?
}

struct SynologySnapshot {
    var nasID: UUID
    var collectedAt: Date
    var connection: ConnectionState
    var system: SynologySystemInfo?
    var resources: SynologyResourceMetrics?
    var storagePools: [SynologyStoragePool]
    var volumes: [SynologyVolume]
}

struct AppAppearanceSettings {
    var colorScheme: AppColorScheme
    var accentColor: ThemeAccentColor
    var appIconName: String
    var reduceRealtimeAnimations: Bool
}

enum AppColorScheme {
    case system
    case light
    case dark
}

struct DashboardSettings {
    var showLatency: Bool
    var colorizeLatency: Bool
    var refreshIntervalSeconds: Int
    var networkUnit: MetricUnitMode
    var diskIOUnit: MetricUnitMode
}

struct DetailLayoutConfiguration {
    var targetKind: ManagedTargetKind
    var cards: [DetailCardConfiguration]
}

struct DetailCardConfiguration: Identifiable {
    var id: UUID
    var kind: DetailCardKind
    var isVisible: Bool
    var order: Int
}

enum DetailCardKind {
    case header
    case cpuUsage
    case cpuLoad
    case memory
    case process
    case network
    case storage
    case ipLocation
    case docker
    case gpu
    case nasSystem
    case nasResource
    case nasStorage
    case nasFiles
    case nasDownloads
}

struct TerminalTheme {
    var name: String
    var fontName: String
    var fontSize: Double
    var backgroundColorHex: String
    var foregroundColorHex: String
    var ansiPalette: [String]
    var cursorStyle: TerminalCursorStyle
}
```

## 8. 安全与隐私

### 8.1 本地敏感数据

- SSH 密码、私钥、passphrase、DSM 密码、DSM sid/cookie 必须存入 Keychain。
- SwiftData 只保存 Keychain 引用 ID，不保存明文。
- 支持 Face ID / Touch ID 解锁后查看和使用敏感配置。
- App 切后台后可自动隐藏敏感界面。

### 8.2 SSH 安全

- 首次连接使用 TOFU 策略记录 Host Key 指纹。
- 后续连接如果 Host Key 变化，必须弹出高风险提示。
- 支持用户查看并重置信任的 Host Key。
- 不默认允许跳过 Host Key 校验，调试模式也要有明显提示。

### 8.3 数据上传策略

- 首版不建设云端服务。
- 不上传服务器地址、NAS 地址、用户名、密钥、DSM 凭据、监控数据、文件列表。
- iCloud 同步如果后续加入，应使用用户个人 iCloud 容器，并在隐私说明中写清楚。
- 未开启 iCloud 同步时，删除 App 会删除本机 SwiftData / SQLite / UserDefaults 中的设备配置；产品需要在设置页明确提示。
- Keychain 可能在卸载后残留，但不能把它当作可靠恢复机制，因为设备列表和 Keychain 引用可能已经丢失。
- 免费用户需要提供手动加密备份/恢复，避免误删 App 后必须完全重新配置。
- 手动备份文件应默认只包含非敏感配置；如后续支持凭据备份，必须端到端加密并要求用户自行保存备份密码。

### 8.4 群晖安全

- 默认建议使用 https 连接 DSM。
- SSL 证书校验默认开启；如果用户关闭，需要明确提示风险。
- DSM 登录失败、2FA 要求、账号锁定、权限不足要给出清晰错误提示。
- 关机、重启、开启/关闭 SSH、删除文件等破坏性操作必须二次确认。
- 不在日志中记录 DSM 密码、sid、cookie、完整文件路径中的敏感部分。

## 9. UI 信息架构

底部固定五个功能区：

- 仪表盘：显示已连接设备，服务器和 NAS 摘要卡片，支持拖拽排序和点击进入详情。
- NAS：显示 NAS 设备卡片和免费 NAS 基础管理能力。
- 设备：新增、编辑、测试连接、删除设备。
- Docker：只显示服务器 Docker 入口列表；NAS Docker 不进入 Docker Tab；点击服务器进入二级容器管理页。
- 设置：会员入口、iCloud 同步、主题、Face ID、安全、反馈、评价等。

底部功能栏视觉：

- iOS 26+ 使用原生 Liquid Glass 作为底栏材质。
- 五个 Tab 的选中态使用玻璃胶囊，用户切换时胶囊在图标之间滑动。
- 滑动过程中可以有轻微形变、折射和高光移动，让底栏有“液态玻璃”感觉。
- 玻璃效果要带一点玫瑰粉 tint，但整体仍以半透明白为主。
- 旧系统使用 `.ultraThinMaterial` / `.thinMaterial` 兜底，保持相近质感。
- 用户开启 Reduce Transparency 或 Reduce Motion 时，底栏切换为更稳定的半透明白底和简单淡入淡出。
- 底栏不能遮挡内容，滚动页面底部要预留安全区域和渐隐遮罩。

主要页面：

```text
Dashboard
├── ServerCard
├── NASCard
├── SortableDeviceCards
└── DeviceDetail

NAS
├── NASCard
├── NASSortableCards
└── NASDetail

Devices
├── AddDeviceEntry
├── AddServerFlow
├── AddNASFlow
├── ConnectionResultFeedback
└── DeviceList

Docker
├── DockerServerEntryList
├── ServerDockerContainerList
└── ServerDockerContainerDetail

AddDeviceFlow
├── AddServerSheet
├── AddNASSheet
├── ConnectionTestingView
├── SuccessAnimationView
└── ConnectionErrorDialog

ServerDetail
├── OverviewCard
├── CPUCard
├── LoadCard
├── MemoryCard
├── ProcessCard
├── NetworkCard
├── StorageCard
└── DockerCard

NASDetail
├── NASOverviewCard
├── NASResourceCard
├── NASStorageCard
├── NASFileBrowser
└── NASDownloadList

Settings
├── PremiumCard
├── iCloudSyncSettings
├── ThemeSettings
├── FaceIDSecuritySettings
├── SecuritySettings
├── DisplaySettings
├── DashboardSettings
├── DetailLayoutEditor
├── TerminalThemeSettings
├── WidgetAppearanceSettings
├── Feedback
├── Rating
└── DataPrivacy
```

视觉方向后续再定，目前只确认原则：

- 原生 iOS 手感。
- 信息密度适中，避免监控页过度装饰。
- 关键状态颜色清晰：正常、警告、危险、离线。
- 卡片承载指标，详情页纵向滚动。
- 图表要服务于判断，不堆过多视觉效果。
- 用户自定义要有边界：主题可以改变个性化表达，但不能牺牲状态识别、可读性和误操作保护。
- 布局编辑页要清楚表达“隐藏”和“删除”的区别，首版实际做隐藏和排序即可。

## 10. 异常与降级

- SSH 连接失败：展示错误类型，如认证失败、超时、Host Key 变化、网络不可达。
- DSM 连接失败：展示协议/端口错误、证书错误、账号密码错误、2FA 要求、权限不足、会话失效、API 不存在等具体原因。
- 命令不存在：隐藏对应模块，例如没有 Docker 就隐藏 Docker 卡片或展示“未检测到 Docker”。
- 权限不足：展示“当前用户无权限读取该指标”。
- 解析失败：记录日志，界面显示上一次成功快照。
- DSM API 不可用：根据 `SYNO.API.Info` 探测结果隐藏对应模块，例如没有 File Station 权限则隐藏文件入口。
- 网络抖动：允许手动刷新，自动重连策略需要节流。
- 服务器负载过高：轮询命令必须轻量，避免 App 本身造成压力。

连接测试错误分类建议：

- `networkUnreachable`：网络不可达，提示检查网络、VPN、局域网。
- `hostNotFound`：域名解析失败，提示检查域名或 IP。
- `portClosed`：端口未开放或被防火墙拦截，提示检查 SSH/DSM 端口。
- `timeout`：连接超时，提示检查服务器在线状态、端口和防火墙。
- `authFailed`：账号或密码错误。
- `privateKeyInvalid`：私钥格式错误或 passphrase 错误。
- `hostKeyChanged`：Host Key 变化，提示存在安全风险。
- `permissionDenied`：连接成功但当前用户权限不足。
- `dsmCertificateInvalid`：DSM SSL 证书无效或自签名。
- `dsmAPIUnavailable`：DSM API 不可用或版本不兼容。
- `dockerUnavailable`：未检测到 Docker 或当前用户无 Docker 权限。

错误弹窗要给出“原因 + 建议操作 + 可执行按钮”，例如：重试、编辑配置、查看诊断。

## 11. 里程碑

### Milestone 0：技术验证

- 创建 SwiftUI 项目。
- 接入 Traversio 或 SwiftNIO SSH，完成密码登录和私钥登录 Demo。
- 执行一条远程命令并返回结果。
- 用 SwiftTerm 渲染一个可交互 SSH 会话。
- 通过 DSM Web API 登录一台测试群晖。
- 调用 `SYNO.API.Info`、`SYNO.Core.System` 或等价接口获取基础信息。
- 调用 File Station 列出一个共享目录。
- 确认 Keychain 存取可用。

验收标准：

- 能连接一台测试服务器。
- 能执行 `uname -a` 并展示输出。
- 能进入基础终端输入命令。
- 能登录一台群晖 NAS 并展示型号、DSM 信息或文件列表。

### Milestone 1：连接对象管理与首页

- 新增 / 编辑 / 删除 SSH 服务器。
- 新增 / 编辑 / 删除群晖 NAS。
- 保存敏感认证信息到 Keychain。
- Dashboard 统一设备列表。
- 底部五栏：仪表盘、NAS、设备、Docker、设置。
- 连接成功后设备自动分发到对应 Tab。
- 仪表盘和 NAS 卡片支持拖拽排序。
- Docker 能力扫描后，Docker 栏自动出现对应服务器入口；点击服务器进入二级容器管理页。
- 测试连接与延迟。
- 在线 / 离线状态。
- 应用外观基础设置：跟随系统 / 亮色 / 暗色、主题色、App 图标预留。
- Dashboard 基础偏好：显示延迟、刷新间隔、减少动画。

验收标准：

- 用户可以配置 SSH 服务器和群晖 NAS，并在首页看到状态。
- SSH 密码、私钥、DSM 密码不出现在本地数据库明文字段中。
- 用户可以改变应用主题色，并且 Dashboard 不影响状态可读性。
- 添加设备成功有动画反馈，失败有明确错误弹窗和下一步操作。

### Milestone 2：监控详情页

- SSH 服务器：
  - 系统信息。
  - CPU、Load、内存、Swap。
  - 网络速率。
  - 磁盘容量。
  - Top 进程。
  - Docker 只读状态。
- 群晖 NAS：
  - 系统状态。
  - 资源监控。
  - 存储空间。
  - File Station 基础目录浏览。
- 状态详情布局：
  - 卡片顺序配置。
  - 卡片显示/隐藏。
  - 恢复默认布局。

验收标准：

- 常见 Ubuntu / Debian / CentOS / Rocky Linux 能展示核心指标。
- DSM 7 群晖能完成登录、状态展示和目录浏览。
- 任一模块采集失败不会导致整个详情页不可用。
- 用户调整卡片顺序后，重新打开 App 仍保持配置。

### Milestone 3：终端体验

- 基础 SSH 终端。
- 复制、粘贴。
- 常用功能键工具栏。
- 断线提示与重连。
- 深浅色主题。
- 终端字体和字号基础配置。

验收标准：

- 能完成常见命令操作。
- 横竖屏、键盘弹出时布局不遮挡输入区域。
- 切换终端主题后 ANSI 颜色和可读性正常。

### Milestone 4：首版打磨

- 错误提示完善。
- 状态缓存。
- 群晖会话失效后的重新登录。
- Face ID / Touch ID。
- 隐私说明。
- 图表和单位格式化。
- 自定义设置导出/重置默认值。
- TestFlight 内测。

验收标准：

- 连续使用 30 分钟无明显内存增长。
- 断网、服务器重启、DSM 退出登录、认证失败等常见异常有清晰反馈。

## 12. 测试计划

### 单元测试

- `/proc/stat` CPU 解析。
- `/proc/meminfo` 内存解析。
- `df` 磁盘解析。
- `/proc/net/dev` 网络解析。
- Docker JSON 行解析。
- DSM API 响应解析。
- File Station 文件列表解析。
- DSM 错误码映射。
- 布局配置排序与隐藏逻辑。
- 主题色和单位配置持久化。
- 单位格式化。

### 集成测试

- SSH 密码登录。
- SSH 私钥登录。
- Host Key 首次信任与变更提示。
- 多服务器轮询。
- 终端会话断开与重连。
- DSM 登录 / 登出。
- DSM sid/cookie 失效后的恢复。
- File Station 目录列表与文件下载。
- 主题设置保存与恢复。
- 状态详情卡片排序、隐藏、恢复默认。

### 手动测试设备

- Ubuntu 22.04 / 24.04。
- Debian 12。
- CentOS 7 或 Rocky Linux 9。
- ARM64 服务器。
- 未安装 Docker 的服务器。
- Docker 已安装但当前用户无权限的服务器。
- DSM 7.x 群晖。
- 开启 2FA 的群晖账号。
- 自签名证书的 DSM。
- 反向代理域名访问的 DSM。
- File Station 权限受限账号。

## 13. 风险与待确认问题

- SwiftNIO SSH 的认证算法兼容性需要实测，老服务器可能只支持旧算法。
- Traversio 的授权边界需要正式确认；如果使用商业授权，要纳入成本和发布计划。
- Traversio 虽然提供高层 SSH/SFTP API，但凭据存储、信任存储、重连、会话恢复仍要由 App 自己设计。
- 部分指标需要 root 或特定工具，例如 `sensors`、`iostat`、Docker 权限。
- 群晖 DSM API 在不同 DSM 版本、套件版本、权限下差异较大，必须通过 `SYNO.API.Info` 动态探测。
- QuickConnect ID 支持需要单独验证，首版不应把它作为强依赖。
- DSM 2FA、SSL 证书、反向代理、账号锁定会增加登录流程复杂度。
- iOS 后台执行能力有限，不能期待长期后台监控。
- 终端体验是高复杂度模块，输入法、复制、键盘工具栏、滚动都需要细磨。
- 自定义主题如果放得太开，容易造成低对比度、状态颜色混乱和页面不一致；首版应使用预设色和受控配置。
- 布局编辑会增加状态组合复杂度，需要保证隐藏卡片后详情页仍然完整、稳定、可恢复。
- SFTP 和群晖 File Station 如果同时做完整文件操作，会显著扩大范围，建议首版先做 File Station 基础浏览和下载。
- 是否支持 Jump Server 会影响 SSH 架构，建议在 Milestone 0 后尽早验证。

## 14. 首版建议结论

建议首版范围控制为：

1. SSH 服务器与群晖 NAS 配置、安全存储。
2. SSH 连接与命令采集。
3. DSM Web API 登录、系统状态、资源监控、存储空间。
4. Dashboard 首页统一设备状态卡片。
5. 服务器详情监控：CPU、内存、网络、磁盘、进程、Docker。
6. 群晖 File Station 基础目录浏览和文件下载。
7. 基础 SSH 终端。
8. 柔光白粉默认主题、Dashboard 偏好、详情页卡片顺序/隐藏、基础终端主题。
9. Face ID / Touch ID 与本地隐私保护。

SFTP 完整文件管理、Jump Server、批量命令、iCloud 同步、小组件高级样式、Docker 管理操作、DSM Download Station、Synology Photos、NAS 关机/重启/SSH 开关放到后续版本。这样可以先做出一个真正可用、稳定、范围清晰且有个人风格的 App，再逐步增加高级能力。

## 15. Swift 实现可行性评估

整体判断：这个项目适合用 Swift / SwiftUI 做，但要注意把功能分层。UI、自定义主题、DSM API、Keychain、安全存储、图表和基础文件下载都比较适合 Swift；SSH 终端、SFTP、QuickConnect、长期后台监控和复杂同步属于高风险模块，需要分阶段验证。

### 15.1 功能难度分级

| 功能 | Swift 实现难度 | 判断 |
| --- | --- | --- |
| SwiftUI 主界面、Tab、列表、卡片 | 低 | SwiftUI 很适合做这类原生工具界面。 |
| 主题色、亮暗模式、App 外观 | 低 | 可通过环境值、配置模型和统一 Design Token 实现。 |
| 状态页卡片排序/隐藏 | 中 | SwiftUI 可做，关键是布局配置持久化和恢复默认。 |
| Dashboard 刷新、状态卡片 | 中 | 技术不难，但要控制刷新频率和并发。 |
| Swift Charts 图表 | 低-中 | CPU、内存、网络趋势图适合用 Swift Charts。 |
| Keychain 保存密码/密钥 | 中 | 可行且成熟，但封装要谨慎，避免明文落库和日志泄露。 |
| Face ID / Touch ID | 低-中 | LocalAuthentication 可直接支持。 |
| DSM Web API 登录 | 中 | URLSession + Codable 可实现，难点在错误码、sid/cookie、2FA、证书。 |
| 群晖系统状态/资源监控 | 中 | API 可行，但不同 DSM 版本和权限要动态探测。 |
| File Station 浏览目录 | 中 | API 可行，注意分页、大目录、权限和编码。 |
| 文件下载到本地 | 中 | URLSessionDownloadTask 可行，需处理后台、暂停、重试、文件名冲突。 |
| 文件上传/移动/删除/重命名 | 中-高 | API 可行，但操作风险高，要做任务队列和二次确认。 |
| SSH 执行命令采集指标 | 中 | Traversio 这类库能降低难度；自己封装 SwiftNIO SSH 会明显更难。 |
| SSH 终端 | 高 | 连接只是第一步，难点在 PTY、输入法、复制、键盘、ANSI 渲染、重连。 |
| SFTP 完整文件管理 | 高 | 如果 Traversio 授权可用会降低难度，否则工作量较大。 |
| Docker 只读监控 | 中 | SSH 执行 docker 命令可行，注意权限和命令输出差异。 |
| Docker 启停/管理 | 中-高 | 命令不难，风险在权限、失败回滚和误操作。 |
| 小组件 | 中 | WidgetKit 可行，但刷新频率受系统限制。 |
| Live Activities | 中 | ActivityKit 可行，但更适合短时状态，不适合长期监控。 |
| iCloud 同步 | 中-高 | 可行，但凭据、冲突合并、跨设备 Keychain 引用要谨慎设计。 |
| QuickConnect ID | 高 | 可能涉及群晖自有解析/中转机制，首版不建议强依赖。 |
| 长期后台监控 | 高/受限 | iOS 后台限制明显，不能按桌面软件思路做常驻监控。 |
| 告警通知 | 中 | 本地通知可做，但持续监控触发受后台限制，后续可考虑用户自建 Agent 或服务器端辅助。 |

### 15.2 Swift 适合的部分

- 原生交互：SwiftUI 可以做出很好的 iOS 手感，适合设置页、卡片、列表、文件浏览和布局编辑。
- 数据安全：Keychain、LocalAuthentication、App Sandbox 都适合做隐私优先产品。
- 并发模型：Swift Concurrency 适合管理 SSH 会话、DSM API 请求、下载任务和状态轮询。
- 图表和动画：Swift Charts + SwiftUI 动画足够覆盖首版监控图表。
- Widget / Live Activities：Apple 生态原生支持，后续扩展自然。

### 15.3 Swift 中需要谨慎的部分

- SSH 协议不要从零实现。优先验证 Traversio；如果授权不合适，再评估 SwiftNIO SSH 的封装成本。
- 终端体验不要低估。一个“能连上”的终端很快，一个“好用”的终端需要大量细节。
- iOS 后台不能做常驻守护进程。App 进入后台后应停止高频轮询，使用最后快照和系统允许的刷新机制。
- iCloud 同步不能同步明文密码。同步配置时要区分普通配置、敏感凭据和每台设备本地授权。
- 群晖 API 要先探测再调用。不要假设所有 DSM 版本、套件和权限都一样。

### 15.4 推荐实现顺序

1. 先做 SwiftUI 壳子、统一设备模型、Keychain、主题配置和本地数据库。
2. 同时做两个技术验证：SSH 命令执行 + DSM 登录/File Station 列目录。
3. 做 Dashboard 统一设备列表和状态卡片。
4. 做 SSH 服务器详情页与群晖 NAS 控制台。
5. 做基础 SSH 终端。
6. 做状态页布局编辑、主题色、终端主题。
7. 再做文件上传、Docker 管理、iCloud 同步、小组件、Live Activities 等增强能力。

### 15.5 结论

Swift 能实现这个项目，而且整体方向合适。首版最稳的范围是：SwiftUI 原生界面 + Keychain + SSH 命令采集 + DSM API + 基础 File Station + 基础终端 + 受控自定义。最不建议首版硬啃的是：QuickConnect 完整兼容、复杂 SFTP、长期后台监控、完整 iCloud 同步和所有 NAS 高危控制操作。

## 16. 视觉设计与动效方案

这个 App 不应该做成普通表格型监控工具。目标体验是：用户打开 App 时先感到“这是我的设备控制台”，随后能快速判断状态、定位异常、进入操作。视觉要有记忆点，但不能牺牲专业工具的清晰度。

参考方向：

- Automation Workflow Mobile App UI：强调柔和配色、圆角模块、清晰网格、复杂流程的可理解性，适合参考“设备能力”和“自动化/快捷操作”的模块组织。
- MoonRow Ticket Sales Analytics Mobile Apps：强调大胆字体、柔和对比、对称布局、实时数据卡片，适合参考 Dashboard 和统计卡片。

参考链接：

- https://dribbble.com/shots/26880791-Automation-Workflow-Mobile-App-UI
- https://dribbble.com/shots/26765480-MoonRow-Ticket-Sales-Analytics-Mobile-Apps

### 16.1 设计关键词

- 模块化：每个设备、指标、快捷操作都是清晰模块，不做拥挤的信息墙。
- 层次感：首页先给结论，详情页再给指标，操作页再给动作。
- 实时感：数据变化要有细微动画，让用户感到设备是“活的”。
- 专业感：颜色、动效、图表都服务于判断，而不是单纯装饰。
- 个性化：主题色、布局、卡片顺序能体现用户偏好。
- 状态优先：异常、警告、离线要比装饰更醒目。

### 16.2 视觉语言建议

首页可以采用“非传统列表”的卡片布局：

- 顶部为设备健康概览：
  - 在线设备数。
  - 异常设备数。
  - 今日流量 / 当前总负载。
  - 最需要关注的设备。
- 中部为重点设备卡：
  - 大卡展示主服务器或 NAS。
  - 小卡展示其他设备。
  - 卡片可以按状态自动分组：需要关注、在线、离线。
- 底部为快捷入口：
  - 打开终端。
  - 浏览文件。
  - 查看 Docker。
  - 查看 NAS 存储。

卡片可以做出差异化：

- SSH 服务器卡：偏技术感，使用终端符号、CPU 波形、网络脉冲线。
- 群晖 NAS 卡：偏存储感，使用容量环、磁盘阵列、文件夹入口。
- Docker 卡：使用容器堆叠和状态点。
- 异常卡：使用高对比边缘色和轻微呼吸提示。

### 16.3 配色系统

默认主界面建议采用“柔光白粉”主题：以淡白色作为主背景，加入轻微粉色渐变作为辅色，让产品从常见的深色/蓝黑监控工具中跳出来。整体感觉应是小清新、眼前一亮、干净、柔和，但仍然保持专业和可读。

主界面的视觉比例建议：

- 70%：暖白、淡白、浅灰白，用于页面背景、卡片主体、表单区域。
- 20%：柔和浅粉，用于渐变背景、选中态、轻量按钮、插画连接线。
- 10%：淡绿色、淡蓝色、淡黄色等点缀，用于健康状态、服务器内部指标和辅助信息。

默认主题方向：

- 主背景：接近白色的暖白，避免纯白刺眼。
- 辅助背景：极浅柔粉，用于页面顶部、卡片外层、插画背景。
- 渐变：白色到淡粉色，角度轻微，不做强烈彩虹渐变。
- 卡片：半透明白、柔和阴影、细边框，形成轻玻璃感。
- 强调色：玫瑰粉到玫瑰粉之间，用于选中态、主按钮、轻量图表强调。
- 点缀色：嫩绿色、淡蓝色、柔和黄色，用于叶子、网络、CPU Load 等细节，避免整个页面只有粉色。
- 服务器内部页面：可以加入淡绿色作为“健康、运行中、资源正常”的辅助色，让状态页更有生命感，但绿色必须低饱和、轻量使用，不要和玫瑰粉形成突兀撞色。

建议初始色板：

```text
ServeraBackground     #FAF8FA
ServeraSurface        #FFFFFF
ServeraTintSoft       #FCECF2
ServeraTint           #F6C9D8
ServeraAccent         #EFA0B8
ServeraAccentDeep     #D96D92
ServeraBorder         #F1DDE5
ServeraTextPrimary    #1F1B20
ServeraTextSecondary  #8C8188
ServeraLeaf           #8FB996
ServeraLeafSoft       #EAF6ED
ServeraSky            #9ECBEF
```

页面背景可以使用：

```text
linear-gradient(180deg, #FAF8FA 0%, #FCECF2 45%, #FFFFFF 100%)
```

或者在 SwiftUI 中用非常轻的 `LinearGradient` / `MeshGradient`，但粉色饱和度要低，避免长时间查看时疲劳。

动态渐变可以参考 Lakr233 的 ColorfulX / Colorful：

- ColorfulX：更适合后续作为可选依赖或技术参考。它是 Metal-backed 的动态多色渐变渲染库，支持 LAB 色彩插值、最多 8 个色点、帧率限制、噪声、渲染缩放和 SwiftUI / UIKit / AppKit 接入，MIT 许可。
- Colorful：更轻量，偏 Apple Card 风格动态模糊背景，适合作为视觉灵感；如果正式集成，优先验证 ColorfulX。

柔光主题下建议不要使用高饱和炫彩渐变，而是做“近白 + 低饱和粉 + 一点淡绿/淡蓝”的缓慢流动：

```text
ServeraMeshA #FAF8FA
ServeraMeshB #FCECF2
ServeraMeshC #FFFFFF
ServeraMeshD #EAF6ED
ServeraMeshE #F6C9D8
```

动态渐变使用边界：

- 首页背景可以非常慢速流动，营造呼吸感。
- 登录、添加设备、空状态页可以使用更明显的柔和渐变。
- 监控详情页只在顶部身份卡或背景边缘使用，不铺满高密度信息区。
- 低电量模式、Reduce Motion、后台恢复后应降低帧率或静态化。
- 如果引入 ColorfulX，首版要限制 `frameLimit` 和 `renderScale`，避免为了视觉效果牺牲电量和滚动性能。

颜色 token 可以参考 metasidd 的 ColorTokensKit-Swift：

- 它使用 OKLCH / CIELab LCH 这类感知均匀色彩空间，适合生成亮度更一致的色阶。
- 它提供语义 token 思路，例如 foreground、background、surface、outline，并支持 light / dark 自动解析。
- 它包含 WCAG 2.x 和 APCA 对比度工具，适合检查柔和浅粉主题下的文字可读性。
- 它是纯 Swift、SPM、零依赖，MIT 许可，最低平台为 iOS 16+、macOS 13+、watchOS 9+、tvOS 16+、visionOS 1+。

在本项目中的用法建议：

- 首版不一定直接引入依赖，可以先参考它的 token 分层方式，建立自己的 `ServeraColorTokens`。
- 如果后续要开放用户自定义主题色，可以评估引入 ColorTokensKit，用 OKLCH 根据一个主色生成完整色阶。
- 柔光白粉主题尤其需要对比度检查，因为浅粉和白色很容易出现“好看但看不清”的问题。
- 语义状态色要独立于品牌 token，例如 warning、critical、offline 不应由用户主题色自动生成。

建议 token 分层：

```text
Primitive Tokens
- servera50 / servera100 / servera200 / servera300
- leaf50 / leaf100 / leaf300
- sky50 / sky100 / sky300
- gray50 / gray100 / gray700 / gray900

Semantic Tokens
- backgroundPrimary
- backgroundSecondary
- surfacePrimary
- surfaceElevated
- foregroundPrimary
- foregroundSecondary
- outlineSubtle
- accentPrimary
- accentSoft
- successSoft
- warningSoft
- critical

Component Tokens
- dashboardBackground
- deviceCardBackground
- deviceCardBorder
- healthRingTrack
- healthRingGood
- terminalToolbarBackground
- nasStorageHealthy
```

建议设计三层颜色：

- 品牌强调色：用户可选，用于按钮、选中态、关键图表。
- 语义状态色：固定含义，不随主题完全改变。
- 数据维度色：用于 CPU、内存、网络、存储、Docker、GPU 等指标。

建议默认语义色：

- 正常：绿色。
- 警告：黄色 / 橙色。
- 危险：红色。
- 离线：灰色。
- 连接中：蓝色。
- 受保护 / 只读：紫色或靛蓝。

建议指标色：

- CPU：青蓝。
- CPU Load：黄色。
- 内存：紫粉。
- 网络上传：橙色。
- 网络下载：蓝色。
- 存储：绿色。
- Docker：蓝色。
- GPU：靛蓝。
- NAS 健康：绿色到橙色渐变，按风险变化。

柔光主题下的注意事项：

- 粉色不能承载“危险”含义，危险仍使用独立红色。
- 卡片背景不要全部粉色，主体仍以白色和浅灰白为主。
- 淡绿色主要用于服务器详情、健康状态、运行中状态、成功状态和 NAS 存储健康，不作为全局主色。
- 粉色和绿色之间要用白色留白过渡，避免大面积粉绿直接相邻造成廉价感。
- 插画可以加入柔粉枝影、淡粉连接线、叶绿色状态点，但不要让监控页变成装饰页面。
- 底部导航、浮动按钮和详情页标题可以带一点粉色玻璃感。
- 深色模式不能简单反转成黑粉，建议使用深灰紫背景 + 低饱和玫瑰色强调。

主题色只能影响品牌层和部分数据层，不能覆盖语义状态色。比如用户选择红色主题时，错误红仍要和品牌红区分开。

### 16.4 卡片布局创意

可以设计几种“不同于常规监控 App”的布局：

1. 设备花园布局
   - 首页不是普通设备列表，而是一片“设备花园”。
   - 每台设备是一朵节点花，中心显示设备名或健康分。
   - 花瓣分别代表 CPU、内存、存储、网络、Docker/NAS 状态。
   - 绿色花瓣代表健康，淡粉代表正常占位，橙色/红色花瓣代表需要关注。
   - 用户点击花朵后展开成设备详情卡。
   - 用户长按拖拽花朵可以排序，固定主设备可以显示为更大的主花。

2. 柔光健康仪表
   - 替代常规圆环图。
   - 5 片花瓣围绕中心：CPU、内存、存储、网络、Docker/NAS。
   - 中心显示设备健康分或在线状态。
   - 花瓣可轻微呼吸，刷新数据时花瓣柔和补间变化。
   - 异常时只让对应花瓣变暖色，不让整张卡大红闪烁。

3. 瀑布指标卡
   - 首页不是等宽列表，而是大小不同的卡片。
   - 异常设备自动变成大卡。
   - 正常设备压缩成小卡，减少视觉噪音。

4. Docker 容器堆叠
   - Docker 首页不要展开容器行。
   - 每台服务器是一条精致入口，重点展示服务器名、地址、运行数和总数。
   - 点击服务器后进入二级容器管理页，再展示完整容器列表和操作。
   - 这种表达比首屏堆容器卡更省空间，也更符合“先选服务器，再管理容器”的心智。

5. NAS 存储抽屉
   - 群晖详情页用“存储空间抽屉”表达多个 Volume。
   - 每个 Volume 是一条柔和抽屉/磁盘槽。
   - 填充宽度表示容量。
   - 健康状态用淡绿色边缘光。
   - 快满时边缘变暖橙。

6. 服务器驾驶舱
   - 详情页顶部像驾驶舱一样展示主状态。
   - 中间是可拖拽卡片。
   - 底部是快捷操作。

首版建议优先实现“设备花园 + 柔光健康仪表 + Docker 容器堆叠 + NAS 存储抽屉”。这些视觉结构能明显区别于 ServerCat、SwiftServer、派派助手，功能仍然是监控和管理，但表达方式有自己的产品记忆点。

### 16.5 动效原则

动效要表达状态，不要只是炫。

- 数据变化：
  - CPU、内存百分比用数字滚动过渡。
  - 柔光健康仪表的花瓣用平滑补间。
  - 容器堆叠的小方块在状态变化时轻微弹跳或变色。
  - NAS 存储抽屉容量变化时用柔和填充动画。
  - 网络速率用细线脉冲。
- 连接状态：
  - 连接中使用轻微扫描线或 SF Symbol variable color。
  - 在线用一次短暂亮起。
  - 离线用淡出和灰化。
- 异常状态：
  - 警告只做低频呼吸。
  - 危险状态可以有更明显边缘闪烁，但必须可关闭。
- 导航转场：
  - 首页卡片进入详情页使用 matchedGeometryEffect，让卡片自然展开。
  - 卡片排序使用弹性回位。
  - 文件夹打开使用层级推进，不做过重转场。
- 下拉刷新：
  - 刷新时卡片顶部出现细微能量条。
  - 刷新完成后关键数字轻微更新动画。

### 16.6 SwiftUI 可用动效技术

首版可以优先使用原生 SwiftUI，不需要引入复杂动画框架：

- `withAnimation` / `.animation(_:value:)`：基础状态切换。
- `matchedGeometryEffect`：设备卡片展开到详情页。
- `contentTransition(.numericText())`：CPU、内存、网络数字变化。
- `symbolEffect`：连接、刷新、下载、警告图标动效。
- `PhaseAnimator`：连接中、扫描中、状态呼吸。
- `KeyframeAnimator`：异常提示、卡片进入、刷新完成动效。
- `TimelineView`：轻量实时波形、网络脉冲、时钟类刷新。
- `Canvas`：高性能绘制 CPU 网格、网络曲线、存储环。
- `ColorfulX`：可选的 Metal 动态多色渐变，用于首页背景、添加设备页、空状态页和品牌视觉层。
- `Material`：卡片背景、浮动底栏、工具条。
- `glassEffect`：iOS 26+ 可用于浮动导航、快捷按钮、关键设备卡；低版本用 `.ultraThinMaterial` 兜底。
- `GlassEffectContainer` + `glassEffectID`：用于底部五栏的液态玻璃选中态滑动和形变。

底部五栏 Liquid Glass 实现建议：

- 用自定义 Tab Bar，不直接依赖系统 `TabView` 默认底栏外观。
- 每个 Tab 是固定宽度或等分宽度按钮，包含 SF Symbol + 中文标签。
- 选中态是一块可移动的 glass capsule，通过 `matchedGeometryEffect` 或 iOS 26 `glassEffectID` 在五个位置之间过渡。
- 胶囊移动时图标颜色、标签权重和背景高光同步变化。
- iOS 26+：
  - `GlassEffectContainer` 包裹整个底栏。
  - 选中胶囊使用 `.glassEffect(.regular.tint(serveraTint).interactive(), in: .capsule)`。
  - 可交互按钮使用 `.buttonStyle(.glass)` 或自定义 glass 背景。
- iOS 18-25：
  - 使用 `.background(.ultraThinMaterial, in: Capsule())`。
  - 选中态用 `matchedGeometryEffect` 做滑动。
- 性能边界：
  - 切换 Tab 才触发动效。
  - 滚动时底栏不要持续重绘。
  - Reduce Motion 下禁用形变，只保留淡入淡出。

需要注意：

- 动效必须尊重 Reduce Motion。
- 低电量模式下应减少实时动画。
- 离屏卡片不应持续动画。
- 高频数据刷新不要触发整页重绘。
- 图表动画要有节流，例如 1 秒内最多更新可见动画一次。

### 16.7 状态驱动视觉

建议建立统一的 `DeviceVisualState`，让所有颜色和动画从状态推导出来：

```swift
enum DeviceVisualState {
    case online
    case connecting
    case warning(reason: String)
    case critical(reason: String)
    case offline
    case readonly
}
```

每种状态对应：

- 主色。
- 辅助色。
- 图标。
- 卡片边缘效果。
- 是否允许动画。
- 是否允许危险操作。

示例：

- `online`：稳定绿色点，轻微数据动画。
- `connecting`：蓝色扫描，SF Symbol 脉冲。
- `warning`：橙色边缘，低频呼吸。
- `critical`：红色强调，减少装饰，突出行动按钮。
- `offline`：灰化卡片，隐藏实时图表，显示最后快照。
- `readonly`：紫色锁标识，隐藏破坏性操作。

### 16.8 关键页面设计建议

Dashboard：

- 开屏先展示一个“设备健康摘要”大卡。
- 下面是动态卡片瀑布流。
- 异常设备自动靠前。
- 用户可以固定某台设备为主卡。

服务器详情页：

- 顶部做服务器身份卡：名称、系统、运行时间、在线状态。
- 中间卡片按用户布局展示。
- CPU 卡可以使用核心网格动画。
- 网络卡可以使用双向流线。
- Docker 卡用容器状态点阵。

群晖详情页：

- 顶部展示 NAS 型号、DSM 版本、温度和运行时间。
- 存储空间用更大视觉权重，像“容量仪表”。
- 文件入口做成可横滑文件夹。
- 下载任务用进度条和状态色。

终端页：

- 终端本体保持专业、克制。
- 工具栏可以更精致：玻璃底栏、快捷键胶囊、连接状态点。
- 主题切换要立即预览。

设置页：

- 外观设置要有实时预览卡。
- 状态详情布局编辑要像系统编辑列表一样清晰。
- 终端主题要有命令预览。

### 16.9 设计落地边界

首版可以做精美，但要控制范围：

- 可以做：
  - 主题色。
  - 自定义布局。
  - 数据数字动画。
  - 卡片进入/展开动效。
  - 环形图、波形、状态点。
  - 关键页面的精致卡片。
- 暂缓做：
  - 复杂 3D 场景。
  - 全屏粒子背景。
  - 长时间持续动效。
  - 过度拟物化。
  - 每个页面都完全不同的视觉系统。

最终目标是“精美、鲜活、有辨识度”，但仍然是一个让用户放心管理服务器和 NAS 的专业工具。

### 16.10 插画与图片资产

细节页面可以加入精美插画，让工具 App 更有完成度。插画不适合塞进高密度监控卡片里，但非常适合用于引导、空状态、错误状态和确认流程。

适合使用插画的场景：

- 添加 SSH 服务器：
  - 笔记本连接服务器机柜。
  - SSH 命令解析。
  - Host Key 验证。
- 添加群晖 NAS：
  - 手机连接 NAS。
  - 磁盘阵列/文件夹。
  - DSM 登录。
- 空状态：
  - 尚未添加设备。
  - 没有 Docker 容器。
  - 文件夹为空。
  - 没有下载任务。
- 错误状态：
  - 连接失败。
  - 证书验证失败。
  - 权限不足。
  - 设备离线。
- 成功状态：
  - 首次连接成功。
  - 文件下载完成。
  - 备份完成。
- 高风险确认：
  - 重启设备。
  - 关机。
  - 删除文件。
  - 停止容器。

插画风格建议：

- 线性 + 柔和填色，避免厚重写实。
- 颜色与当前主题色联动，但保留状态语义色。
- 默认跟随柔光白粉主题：暖白底、淡粉连接线、玫瑰粉强调点、少量叶绿色点缀。
- 服务器、NAS、终端等技术元素用深灰紫线条，而不是纯黑，整体更温和。
- 主体简单清晰，例如设备、文件、网络连接、终端窗口。
- 可以有少量粒子、连接线、状态点，增强科技感。
- 不使用大面积纯装饰背景，避免抢走表单和按钮注意力。
- 尺寸保持克制，通常放在页面顶部 120-180pt 高度。

资产实现建议：

- 首选矢量 PDF 或 SVG 转 PDF，便于适配深浅色和不同尺寸。
- 需要动效的插画可以拆成多层 SwiftUI Shape / Canvas，做轻微浮动、连接点流动、状态灯闪烁。
- 首版可以先用 5-8 张核心插画：
  1. 添加 SSH 服务器。
  2. 添加群晖 NAS。
  3. 空设备列表。
  4. 连接失败。
  5. 权限/证书风险。
  6. 文件夹为空。
  7. 下载完成。
  8. 只读模式/安全保护。
- 如果后续引入 AI 生成插画，要统一线宽、圆角、阴影、色板，不能每张图像风格不同。

具体页面示例：

- Add Machine 页面：
  - 顶部放“电脑 -> 加密通道 -> 服务器”的插画。
  - 中间是 Quick Paste，支持粘贴 `ssh user@host -p 22` 自动解析。
  - 下方是 Host、Port、Name 表单。
  - Next 后进入认证和 Host Key 验证。
- Add NAS 页面：
  - 顶部放“手机 -> DSM -> NAS 磁盘阵列”的插画。
  - 表单展示协议、地址、端口、账号、密码、SSL 校验。
  - 登录成功后用小动效显示 NAS 状态卡。
- 连接失败页：
  - 插画表现断开的连接线。
  - 文案直接给原因和下一步：检查端口、账号、证书、网络。
  - 按钮：重试、编辑连接、查看诊断。

插画与动效边界：

- 插画不能替代状态信息，必须有明确文字和操作。
- 错误状态的插画不能过于轻松，避免弱化风险。
- 高风险操作确认页不要使用过度活泼的图像。
- 动态插画应支持 Reduce Motion，关闭后保持静态版本。

## 17. 商业化与收费功能规划

商业化原则：产品重点放在服务器管理，NAS 管理作为免费附加宣传点和获客亮点。用户可以免费体验 NAS 状态、基础控制和轻量 Docker 信息；真正的 Pro 价值放在服务器高级管理、Docker 深度管理、数据同步、设备规模、文件预览/编辑和高级个性化上。不要把安全底线、基础连接、删除设备这类基础权利做成付费墙。

### 17.1 免费版建议

免费版要足够可用，建立信任和口碑：

- 添加少量 SSH 服务器，例如 2-3 台。
- NAS 管理免费开放，作为产品宣传亮点，但功能范围控制在基础管理。
- SSH 服务器基础状态监控。
- 群晖 NAS 基础状态监控：
  - 系统信息。
  - CPU / 内存 / 网络。
  - 存储空间。
  - 温度/散热状态。
  - 开关机/重启，必须二次确认。
  - Docker 容器基础列表和状态。
- Dashboard 基础卡片。
- 基础 SSH 终端。
- NAS File Station 基础目录浏览。
- 基础主题：默认柔光白粉主题 + 跟随系统亮暗模式。
- Keychain 安全存储。
- Face ID / Touch ID。
- 手动刷新。
- 手动加密备份：
  - 免费开放，不应作为 Pro 付费墙。
  - 用于防止用户未开启 iCloud 同步时误删 App 后彻底丢失配置。
  - 备份内容包含设备基础配置、排序、标签、主题和布局。
  - 密码、私钥、DSM Token 等敏感凭据默认不明文导出；首版可选择不导出凭据，让用户恢复后重新验证。
  - 设置页保留两个独立入口：“导出加密备份”和“恢复备份”。
  - 用户点击“导出加密备份”时，弹窗只展示导出说明和导出按钮。
  - 用户点击“恢复备份”时，弹窗只展示恢复说明和选择备份文件按钮，不在恢复流程顶部再放导出按钮，避免流程混乱。
  - 后续可做“包含凭据的加密备份”，必须由用户设置备份密码并明确风险。

免费版限制建议：

- 设备数量限制，而不是核心功能完全不可用。
- 历史数据只保留短时间，例如最近 1 小时或最近 20 条快照。
- 自定义布局只允许基础排序，更多模板进入 Pro。
- 服务器文件预览/编辑进入 Pro。
- NAS 高级文件操作可以后续再决定是否免费，首版先不作为主要付费点。

### 17.2 Pro 订阅功能

适合做订阅的功能，通常是持续带来价值、需要维护和迭代的能力：

- 无限设备数量。
- iCloud 同步：
  - 设备配置同步。
  - 主题和布局同步。
  - 命令片段同步。
  - 注意：敏感凭据仍要谨慎处理，不同步明文。
  - 用户删除 App 后重新下载，只要之前开启过 iCloud 同步，服务器和 NAS 基础配置应自动恢复。
- 高级 Dashboard：
  - 多种首页布局模板。
  - 主设备固定。
  - 异常优先视图。
  - 自定义设备分组。
- 历史趋势：
  - 24 小时 / 7 天 / 30 天轻量趋势。
  - CPU、内存、网络、存储变化。
  - 容器异常历史。
- 告警：
  - 磁盘快满。
  - CPU/内存持续高。
  - 服务器离线。
  - Docker 容器退出。
  - NAS 存储池异常。
  - 注意：纯本地告警受 iOS 后台限制，需要清晰说明。
- 小组件和 Live Activities：
  - 多设备小组件。
  - 自定义小组件样式。
  - 锁屏状态。
  - 实时活动。
- 高级终端：
  - 多会话。
  - 终端主题。
  - 字体/字号/ANSI 色板。
  - 命令片段。
  - 常用快捷键面板。
- 服务器文件能力：
  - SFTP 文件浏览。
  - 文件预览。
  - 文本文件编辑。
  - 上传/下载。
  - 移动、复制、重命名、删除。
  - 多文件操作和传输队列。
- 自动化与快捷操作：
  - 自定义命令模板。
  - 批量命令。
  - 定时执行，本地触发能力受限，需谨慎设计。
  - 一键查看日志、重启服务、清理缓存等。
- Docker 深度管理：
  - 启动/停止/重启容器。
  - 查看容器日志。
  - 容器资源历史。
  - Compose 项目识别。
- 数据同步：
  - iCloud 同步。
  - 多设备主题和布局同步。
  - 命令片段同步。
  - 设备分组同步。
- NAS 非重点 Pro 扩展，后续可选：
  - Download Station。
  - Synology Photos 浏览/备份。
  - 任务计划。
  - 套件状态。
  - 更细的 Container Manager 管理。
- 高级个性化：
  - 多套主题。
  - 自定义 App 图标。
  - 动态渐变背景。
  - 高级卡片模板。
  - 终端主题导入。

### 17.3 一次性买断功能

一次性买断适合用户感知明确、维护成本较低的功能：

- Pro Lifetime 永久版。
- 高级主题包。
- App 图标包。
- 终端主题包。
- 卡片布局模板包。
- NAS 插画包或季节主题包。

建议保留 Lifetime 选项，因为这类工具 App 的用户经常偏好一次性购买。

### 17.4 不建议收费的功能

这些能力不建议收费，否则会伤害信任：

- 本地安全存储。
- 删除设备。
- 导出自己的配置，敏感信息除外。
- Host Key 安全提示。
- SSL 证书风险提示。
- 基础错误诊断。
- 基础隐私保护。
- 基础连接测试。
- 基础离线提示。
- NAS 基础状态查看。
- NAS 开关机/重启。
- NAS Docker 容器基础状态查看。

### 17.5 收费模式建议

推荐组合：

- 免费版：可用但有限制。
- Pro 月订阅：适合轻度尝试。
- Pro 年订阅：主推，价格更划算。
- Lifetime：高价一次性买断，面向工具型用户。

可考虑的定价层级，后续按市场调研调整：

- 月订阅：¥12-18。
- 年订阅：¥88-128。
- Lifetime：¥198-298。

中国区用户对订阅较敏感，建议 Lifetime 作为重要选项；海外区可以更偏订阅。

### 17.6 付费墙设计

付费墙应该在用户理解价值后出现：

- 用户添加超过免费设备数量时。
- 用户尝试 iCloud 同步时。
- 用户进入高级主题/布局模板时。
- 用户开启历史趋势超过免费范围时。
- 用户尝试服务器 Docker 深度管理时。
- 用户尝试服务器文件预览/编辑时。
- 用户尝试 SFTP 高级文件操作时。

付费墙不要在首次打开就强推。可以在设置页放 Premium 卡片，但不打断核心流程。

高级功能未解锁时，界面可以展示出来，但使用精美毛玻璃遮罩表达“可预览、需解锁”：

- 列表页只展示对象本身，例如 Docker 栏只显示已连接服务器卡片，不直接展示付费提示。
- 用户点进高级详情页后，再用毛玻璃遮罩弱提示未解锁能力。
- 遮罩下方保留真实布局轮廓，让用户知道解锁后获得什么。
- 非设置页不要反复出现“Pro”“收费”“查看会员”按钮，避免打断用户和造成强推感。
- Docker 详情这类业务页面只放克制说明，例如“容器详情可在设置中了解更多管理能力”。
- 唯一明确会员入口放在设置页顶部“获取 Pro”卡片。
- 用户点击“获取 Pro”后，再用弹窗或半屏 sheet 清晰展示会员功能、价格和权益。
- 不要遮住基础功能，不要让用户误以为 App 出错。
- 遮罩视觉应符合柔光白粉主题：半透明白、淡粉边缘、高斯模糊、轻阴影。
- 对文件内容、日志、敏感信息不能用“先渲染再模糊”的方式泄露，应使用模拟占位数据或服务端/本地权限判断后再加载真实内容。

### 17.7 首版商业化建议

首版先预留 StoreKit 2 和权益模型，但不一定一开始就强推复杂订阅。建议首版收费点控制在：

1. 设备数量上限。
2. 高级主题和 App 图标。
3. 详情页布局模板。
4. 终端主题。
5. 服务器 Docker 深度管理。
6. 服务器文件预览/编辑。
7. iCloud 同步，若技术成熟再开放。
8. 历史趋势，若本地快照稳定再开放。

NAS 基础管理建议免费开放，用来做差异化宣传和吸引用户安装；服务器高级能力才是主要付费抓手。这样不会阻碍用户体验，又能尽早验证付费意愿。

## 18. 当前实现状态与产品边界修订

> 更新日期：2026-05-29  
> 说明：本节用于同步当前 Servera 原型和代码实现后的最新产品边界，优先级高于前文早期草案中不一致的描述。

### 18.1 当前底部 Tab

当前 App 使用五个主入口：

- Server：SSH 服务器首页、服务器星群、服务器卡片和服务器详情。
- NAS：群晖 NAS 首页、NAS 详情、文件、控制面板、NAS Docker。
- 设备：新增和编辑 SSH Server / 群晖 NAS。
- Docker：只展示 SSH Server Docker，不展示 NAS Docker；首页是服务器入口列表，二级页才展示容器管理。
- 设置：备份、主题、安全、Pro 权益说明。

### 18.2 NAS 免费边界

NAS 是当前产品的获客重点，NAS 页面内能力全部按免费功能设计，不接 Pro 锁定：

- NAS 状态查看免费。
- NAS 资源监控免费。
- NAS 存储卷与文件管理免费。
- NAS Docker / Container Manager 查看与操作免费。
- NAS 控制面板模块免费。
- 后续 NAS Docker 启停、日志、重启、删除、文件操作、控制面板管理能力也按免费方向设计。

需要避免的文案：

- 不在 NAS 页面写“Pro”“高级”“解锁”“收费”“会员”等暗示。
- 不把 NAS Docker 或 NAS 管理写进 Pro 卖点。
- 不让用户误解 NAS 能力是试用或付费功能。

Server Docker 的 Pro 边界可以保留。Docker Tab 继续只展示 SSH Server Docker；NAS Docker 只出现在 NAS 栏和 NAS 详情页。

### 18.3 当前已落地的关键能力

#### SSH Server

- 添加服务器。
- 编辑服务器。
- 删除服务器。
- SSH Host Key 首次信任确认。
- Host Key 变化后的“确认重装，更新并继续”流程。
- SSH 连接默认直连，避免被系统代理误伤。
- 服务器状态采集：CPU、内存、磁盘、网络、运行时间、进程。
- Server Docker 采集。
- 当 SSH 用户不在 docker 组但有 sudo 权限时，Docker 只读采集自动使用 sudo 兜底，对用户无感。
- Server 首页星群气泡视觉入口。

#### NAS

- 添加 NAS 时从 NAS 页进入设备页，默认选中“群晖 NAS”。
- NAS 默认协议 HTTP、默认端口 5000。
- NAS 首页和 NAS 详情展示真实 DSM 状态。
- NAS 首页布局当前为：概览、资源指标、控制面板、存储空间、NAS Docker。
- NAS 详情页同样保留 NAS Docker，但 Docker 放在资源和存储之后。
- 多台 NAS 时首页展示 NAS 设备列表；单台 NAS 时展示完整概览。
- NAS 删除、编辑、下拉刷新正常。

#### NAS Docker

- DSM Docker / Container Manager 容器列表读取。
- 展示容器名称、状态、CPU、内存、运行时间。
- 运行中容器优先排序。
- NAS 首页轻量展示，NAS 详情展示完整列表。
- 容器启动、停止、重启、删除、刷新。
- 删除、停止、重启需要二次确认。
- 日志优先走 DSM API；DSM 返回空日志时可走 SSH 兜底。
- 日志后续仍需继续优化：只显示容器日志，减少系统/命令噪声，并完善筛选。

#### NAS 文件管理

- 点击存储卷进入 File Station 文件浏览。
- 显示共享文件夹和目录树。
- 支持上传、下载/分享、新建文件夹、重命名、移动、删除。
- 上传同名文件时弹覆盖确认。
- DSM 权限不足、路径不存在、参数错误、空间不足等都需要明确提示，不伪造成功。

#### NAS 控制面板

控制面板放在 NAS 页面资源四宫格下方、存储空间上方。模块为：

- 用户与群组
- 外部访问
- 网络
- 终端机
- 信息中心
- 更新还原

交互规则：

- 点击控制面板模块进入独立二级页面。
- 二级页顶部不放横向模块切换胶囊。
- 用户通过系统返回或右滑返回控制面板。
- 高风险系统设置第一版尽量只读或给 DSM 控制台入口，不直接提供危险开关。

### 18.4 用户与群组最新设计

用户与群组模块当前收口为“清爽列表 + 用户二级详情页”。

列表页：

- 只展示用户账号列表。
- 不再重复展示用户群组分段入口。
- 行内展示：正常/停用状态、用户名、当前账号标记、管理员标记、右侧箭头。

用户详情页：

- 不使用底部抽屉。
- 不使用顶部 Tab。
- 只保留三类核心能力：
  - 顶部用户状态摘要。
  - 账号与密码。
  - 用户群组。
- 删除描述、电子邮件、禁止自行改密、共享文件夹权限、空间配额。
- 登录账号名允许修改，但 `admin`、`guest` 等内置账号不开放改名。
- 修改用户名、修改密码属于高危操作，保存前必须弹窗确认。
- 如果当前 App 使用的 DSM 登录账号被改名成功，本地 NAS 账号要同步更新，避免后续刷新认证失败。

### 18.5 外部访问最新设计

外部访问当前保留：

- DSM 外部地址。
- DDNS。
- 打开 DSM Web 控制台入口。

QuickConnect 编辑块已删除。原因：

- 当前 DSM 写接口在不同版本上不稳定，容易返回 101/102/103/104/400。
- 保存失败容易让用户误解为 App 问题。
- 对大多数用户来说，通过 App 修改 QuickConnect 不是高频必要能力。

QuickConnect 后续只可作为只读状态或 DSM 控制台跳转提示，不在 App 内做复杂编辑。

### 18.6 当前原型图清单

原型目录：`Docs/YX`

开源版本只保留一个原型总览页，避免目录过大和重复维护：

- `prototype.html`：集中展示 Server、NAS、Docker、设置、控制面板等核心界面。
- `prototype.css`：原型样式。
- `prototype.html.png`：原型总览截图，便于不开浏览器快速查看。

后续如需单独页面，可从 `prototype.html` 按模块再拆分生成。

### 18.7 当前回归检查重点

每轮涉及 UI 或业务逻辑后，至少检查：

- 从 NAS 页点 `+`，设备页默认进入群晖 NAS，端口为 5000。
- 从 Server 页点 `+`，设备页默认进入 SSH 服务器，端口为 22。
- NAS 页面不出现 Pro/高级/解锁/收费暗示。
- NAS Docker 不进入 Docker Tab。
- Docker Tab 只显示 SSH Server Docker。
- QuickConnect 编辑块不出现在外部访问页。
- 用户详情页不出现描述、邮箱、禁止自行改密、共享文件夹权限、空间配额。
- 修改用户名和密码必须二次确认。
- NAS 文件上传失败、权限失败不伪造成功。
- Host Key 未知和 Host Key 变化都必须明确确认。
