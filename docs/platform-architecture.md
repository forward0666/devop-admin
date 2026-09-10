# Cloud Console 平台化架构设计

## 一、核心原则

1. **cloud-console** 是唯一的 App Shell / 主框架，不含任何业务逻辑
2. 所有业务服务独立部署、独立子域名、独立前端应用
3. 子服务通过 **iframe** 嵌入主框架，零运行时耦合
4. 子服务通过 **App Contract** 接入，新增服务只需注册 + 实现协议
5. 主框架永远不需要修改业务代码

## 二、架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    cloud-console (App Shell)                  │
│                    console.192.168.86.12.nip.io               │
│                                                              │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ Top Nav │ │ Services │ │  Home    │ │  iframe Container│ │
│  │ (全局)   │ │ Catalog  │ │ Dashboard│ │  (子服务加载区)    │ │
│  └─────────┘ └──────────┘ └──────────┘ └──────────────────┘ │
│                                                              │
│  App Contract Registry (服务注册表)                            │
│  ├─ iam → iam.192.168.86.12.nip.io                          │
│  ├─ cloudflare → cloudflare.192.168.86.12.nip.io            │
│  ├─ telegram → telegram.192.168.86.12.nip.io                │
│  └─ ... (未来新服务自动发现)                                   │
└──────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  iam-console    │ │ cloudflare-console│ │ telegram-console │
│  iam.xxx.nip.io │ │ cf.xxx.nip.io   │ │ tg.xxx.nip.io   │
│                 │ │                 │ │                 │
│  独立 Nuxt App  │ │  独立 Nuxt App  │ │  独立 Nuxt App  │
│  独立路由/页面   │ │  独立路由/页面   │ │  独立路由/页面   │
│  独立 API 层    │ │  独立 API 层    │ │  独立 API 层    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│                     API Gateway                              │
│                  gateway.devops-admin:8081                    │
│                                                              │
│  /api/iam/** → manage  /api/cloudflare/** → cloudflare svc   │
│  /api/telegram/** → bot  /api/settings/** → manage           │
└──────────────────────────────────────────────────────────────┘
```

## 三、App Contract 协议

### 3.1 服务注册（主框架侧）

每个接入的服务在主框架注册一个配置对象：

```typescript
// cloud-console/app/registry/services.ts
export interface ServiceRegistration {
  id: string                    // 唯一标识: 'iam', 'cloudflare'
  name: string                  // 显示名: 'IAM', 'Cloudflare'
  description: string           // 描述
  icon: string                  // 图标 URL 或 emoji
  url: string                   // 子服务 URL: 'https://iam.192.168.86.12.nip.io'
  category: string              // 分类: 'Security', 'Network', 'DevOps'
  navItems?: NavItem[]          // 导航菜单项（子服务上报或静态配置）
  permissions?: string[]        // 所需权限
  status: 'active' | 'beta' | 'maintenance'
}
```

### 3.2 子服务通信协议（postMessage）

主框架与子服务通过 `window.postMessage` 通信：

```typescript
// 通信消息类型
interface AppMessage {
  type: string
  payload: any
  source: 'shell' | 'service'
  serviceId: string
  timestamp: number
}

// 消息类型定义
const MESSAGE_TYPES = {
  // Shell → Service
  'shell:auth':          // 传递认证 token + 用户信息
  'shell:theme':         // 传递主题配置
  'shell:navigate':      // 通知子服务路由变化
  'shell:resize':        // 容器尺寸变化

  // Service → Shell
  'service:ready':       // 子服务加载完成
  'service:navigate':    // 请求主框架跳转
  'service:title':       // 更新页面标题
  'service:nav':         // 上报导航菜单
  'service:notification': // 发送通知
  'service:resize':      // 请求调整 iframe 高度
  'service:error':       // 错误上报
}
```

### 3.3 子服务必须实现的接口

```typescript
// 子服务页面必须包含以下 meta 标签
<meta name="app-contract" content="1.0">
<meta name="service-id" content="iam">
<meta name="service-name" content="IAM">

// 子服务必须监听以下 postMessage
window.addEventListener('message', (event) => {
  if (event.data.type === 'shell:auth') {
    // 接收 token，设置本地认证状态
  }
  if (event.data.type === 'shell:theme') {
    // 接收主题，应用全局样式
  }
})

// 子服务加载完成后必须发送
window.parent.postMessage({
  type: 'service:ready',
  serviceId: 'iam',
  payload: { navItems: [...], title: 'IAM Dashboard' }
}, '*')
```

### 3.4 子服务 SDK（共享 NPM 包）

```typescript
// @cloud-console/sdk — 子服务引入此包即可快速接入
import { useAppShell } from '@cloud-console/sdk'

const { auth, theme, navigate, setTitle, onMessage } = useAppShell()

// 自动接收 shell:auth 消息，设置本地 token
auth.onAuth((token, user) => {
  // token 和 user 自动可用
})

// 请求主框架导航
navigate('/services')

// 设置页面标题（显示在主框架顶部）
setTitle('IAM > Roles')

// 监听主题变化
theme.onThemeChange((theme) => {
  document.documentElement.setAttribute('data-theme', theme)
})
```

## 四、主框架职责（cloud-console）

### 4.1 只保留的功能

| 功能 | 路由 | 说明 |
|------|------|------|
| 首页 | `/` | Dashboard，展示服务目录 + 概览 |
| 服务目录 | `/services` | 所有已注册服务列表 |
| 服务详情 | `/services/:id` | 服务信息 + 进入按钮 |
| 全局导航 | 顶部栏 | 服务切换、用户菜单、搜索 |
| 子服务容器 | `/app/:serviceId/*` | iframe 加载子服务 |
| 登录 | `/login` | 全局登录页（如需要） |

### 4.2 服务目录页（/services）

自动从注册表读取所有服务，展示卡片列表。

### 4.3 子服务加载页（/app/:serviceId/*）

```
/app/iam/roles → iframe 加载 https://iam.192.168.86.12.nip.io/roles
/app/cloudflare/dns → iframe 加载 https://cloudflare.192.168.86.12.nip.io/dns
```

URL 映射规则：`/app/{serviceId}/{path}` → `{serviceUrl}/{path}`

## 五、独立服务模板

每个独立服务基于统一模板创建：

```
services/
├── iam-console/           # IAM 前端
│   ├── app/
│   │   ├── pages/         # 独立页面
│   │   ├── components/    # 业务组件
│   │   ├── layouts/       # 可选：子服务自己的布局
│   │   └── composables/   # 业务逻辑
│   ├── server/
│   │   └── api/           # 独立 API 层
│   ├── Dockerfile
│   ├── nuxt.config.ts
│   └── package.json
├── cloudflare-console/
├── telegram-console/
└── ...（未来新服务）
```

### 子服务 nuxt.config.ts 模板

```typescript
export default defineNuxtConfig({
  modules: ['@cloud-console/theme'], // 共享主题包
  app: {
    head: {
      meta: [
        { name: 'app-contract', content: '1.0' },
        { name: 'service-id', content: 'iam' },
        { name: 'service-name', content: 'IAM' },
      ]
    }
  }
})
```

### 子服务 app.vue 模板

```vue
<script setup>
import { useAppShell } from '@cloud-console/sdk'
const { auth, theme, setTitle } = useAppShell()

// 接收认证信息
auth.onAuth((token, user) => {
  // 设置本地认证状态
})

// 通知主框架加载完成
onMounted(() => {
  setTitle('IAM')
})
</script>

<template>
  <NuxtPage />
</template>
```

## 六、共享 NPM 包

| 包名 | 用途 | 依赖 |
|------|------|------|
| `@cloud-console/sdk` | App Shell 通信 SDK | 零依赖 |
| `@cloud-console/theme` | 共享 CSS 变量 + Tailwind 预设 | tailwindcss |
| `@cloud-console/icons` | 共享图标库 | 无 |
| `@cloud-console/api-client` | 统一 API 请求封装 | ofetch |

这些包独立发布到私有 npm registry 或直接 git 引用。

## 七、部署架构

| 服务 | 子域名 | K8s Deployment | Ingress |
|------|--------|----------------|---------|
| 主框架 | console.xxx.nip.io | cloud-console | 已有 |
| IAM | iam.xxx.nip.io | iam-console (新建) | 新建 |
| Cloudflare | cloudflare.xxx.nip.io | cloudflare-console (新建) | 新建 |
| Telegram | telegram.xxx.nip.io | telegram-console (新建) | 新建 |

每个子服务独立 Dockerfile、独立 Helm chart、独立 ArgoCD Application。

## 八、实施顺序

### Phase 1: 主框架改造
1. 创建 `@cloud-console/sdk` 包（postMessage 通信）
2. 创建 `@cloud-console/theme` 包（共享样式）
3. 改造 cloud-console：移除所有业务页面，只保留 App Shell
4. 实现服务注册表 + 子服务 iframe 加载器
5. 实现 /app/:serviceId/* 路由

### Phase 2: IAM 独立化（先拆最复杂的验证方案）
1. 创建 iam-console 独立 Nuxt 项目
2. 迁移 IAM 页面到 iam-console
3. 实现 App Contract（接入 SDK）
4. 独立部署 + Ingress 配置
5. 在主框架注册 IAM 服务

### Phase 3: 其他服务独立化
1. Cloudflare → cloudflare-console
2. Telegram → telegram-console
3. Settings/Admin/Projects → 暂留主框架或独立

### Phase 4: 共享包发布
1. 发布 @cloud-console/sdk
2. 发布 @cloud-console/theme
3. 文档化 App Contract 规范
4. 新增服务接入指南
