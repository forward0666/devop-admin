# IAM 微服务架构设计

## 一、服务职责与数据存储

### 1. user 服务（用户主体管理）

**职责**：用户账号全生命周期管理

**存储数据**：
| 表名 | 字段 | 说明 |
|------|------|------|
| `iam_user` | id, username, phone, email, nickname, avatar, status(enabled/disabled), department_id, created_at, updated_at | 用户基础档案 |
| `iam_user_tag` | id, user_id, tag_key, tag_value | 用户标签 |
| `iam_user_extend` | id, user_id, attr_key, attr_value | 扩展属性 |

**不处理**：密码、Token、权限、登录、MFA

---

### 2. login 服务（登录流程编排）

**职责**：登录/登出/会话管理，纯编排服务

**存储数据**：
| 表名 | 字段 | 说明 |
|------|------|------|
| `login_session` | id, user_id, token, refresh_token, ip, user_agent, expires_at, created_at | 会话记录 |
| `login_audit_log` | id, user_id, action(login/logout/refresh), ip, user_agent, result(success/fail), fail_reason, created_at | 登录审计 |

**不存储**：密码哈希、MFA密钥、权限策略

---

### 3. security 服务（安全原子能力）

**职责**：安全校验原子能力，对外暴露能力接口

**存储数据**：
| 表名 | 字段 | 说明 |
|------|------|------|
| `sec_password` | id, user_id, password_hash, salt, algo(bcrypt/argon2), created_at, updated_at | 密码哈希（**唯一存储**） |
| `sec_mfa` | id, user_id, mfa_type(totp/sms/email), secret, backup_codes, enabled, created_at | MFA 密钥 |
| `sec_risk_rule` | id, rule_type, condition_json, action(block/verify/notify), enabled | 风控规则 |
| `sec_risk_event` | id, user_id, ip, event_type, risk_level, action_taken, created_at | 风控事件 |
| `sec_bruteforce` | id, ip, user_id, fail_count, locked_until, created_at | 暴力破解拦截 |
| `sec_password_policy` | id, min_length, require_upper, require_lower, require_digit, require_special, max_age_days, history_count | 密码策略 |
| `sec_blacklist` | id, target_type(ip/email/phone/user_id), target_value, reason, expires_at | 黑名单 |

**不处理**：登录业务流程、Token签发、权限查询

---

### 4. manage 服务（IAM 全局权限管理）

**职责**：RBAC 权限管理，对外暴露权限查询接口

**存储数据**：
| 表名 | 字段 | 说明 |
|------|------|------|
| `iam_role` | id, name, arn, description, is_system, created_at | 角色 |
| `iam_policy` | id, name, arn, policy_doc(JSON), type(inline/managed), created_at | 权限策略 |
| `iam_user_role` | id, user_id, role_id | 用户-角色绑定 |
| `iam_role_policy` | id, role_id, policy_id | 角色-策略绑定 |
| `iam_permission` | id, user_id, resource, action, effect(allow/deny), conditions | 最终权限（计算后） |
| `iam_tenant` | id, name, arn, status | 租户 |
| `iam_config` | id, config_key, config_value | IAM 全局配置 |

**不处理**：用户实体、登录认证、密码安全

---

## 二、服务依赖关系图

```
                    ┌──────────────┐
                    │   API Gateway │ :32101
                    │  (路由 + 认证) │
                    └──────┬───────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
   ┌──────────┐    ┌──────────┐    ┌──────────┐
   │  login   │    │   user   │    │  manage  │
   │ :8080    │    │ :8080    │    │ :8080    │
   └────┬─────┘    └──────────┘    └──────────┘
        │                ▲                ▲
        │   ┌────────────┤                │
        │   │            │                │
        ▼   ▼            │                │
   ┌──────────┐          │                │
   │ security │──────────┘                │
   │ :8080    │───────────────────────────┘
   └──────────┘
```

**依赖矩阵**：

| 服务 | 依赖 | 被依赖 |
|------|------|--------|
| user | 无 | login |
| security | 无 | login, (manage 密码策略查询) |
| manage | 无 | login |
| login | user, security, manage | Gateway |

**规则**：单向箭头，禁止循环依赖。

---

## 三、核心业务流程

### 1. 注册流程

```
用户 → Gateway → login(/register)
  │
  ├─→ [1] user  POST /user/create
  │     创建用户档案，返回 user_id
  │
  ├─→ [2] security  POST /password/set
  │     存储密码哈希（user_id + password）
  │
  ├─→ [3] manage  POST /role/assign
  │     分配默认角色（如 "viewer"）
  │
  └─→ [4] 返回注册成功
```

### 2. 登录流程

```
用户 → Gateway → login(/auth)
  │
  ├─→ [1] user  GET /user/by-username?username=xxx
  │     校验账号存在 + 是否禁用
  │     失败 → 返回"账号不存在/已禁用"
  │
  ├─→ [2] security  POST /password/verify
  │     {user_id, password}
  │     校验密码 + 暴力破解检测 + 黑名单检查
  │     失败 → 返回"密码错误/账号锁定"
  │
  ├─→ [3] security  POST /mfa/verify (如 MFA 已启用)
  │     {user_id, mfa_code}
  │     校验 MFA 码
  │     失败 → 返回"MFA 验证失败"
  │
  ├─→ [4] security  POST /risk/evaluate
  │     {user_id, ip, user_agent}
  │     风控评估 → pass / challenge / block
  │     block → 返回"风控拦截"
  │
  ├─→ [5] manage  GET /permission/user?user_id=xxx
  │     查询用户权限列表
  │
  ├─→ [6] login 本地：
  │     签发 JWT Token + Refresh Token
  │     创建会话记录
  │     记录登录审计日志
  │
  └─→ [7] 返回 {token, refresh_token, permissions, user_info}
```

### 3. 登出流程

```
用户 → Gateway → login(/logout)
  │
  ├─→ [1] 验证 Token 有效性
  ├─→ [2] 标记会话失效（DB + Redis）
  ├─→ [3] 记录登出审计日志
  └─→ [4] 返回登出成功
```

### 4. 接口鉴权流程（Gateway AuthFilter）

```
请求 → Gateway AuthFilter
  │
  ├─→ [1] 白名单路径？ → 放行
  │
  ├─→ [2] 提取 Authorization: Bearer <token>
  │     无 Token → 401
  │
  ├─→ [3] 本地验证 JWT 签名 + 过期时间
  │     失败 → 401
  │
  ├─→ [4] Redis 查会话是否有效
  │     无效 → 401
  │
  ├─→ [5] manage GET /permission/check
  │     {user_id, resource, action}
  │     检查用户是否有权限访问该资源
  │     无权限 → 403
  │
  └─→ [6] 转发请求到后端服务
```

### 5. 权限分配流程

```
管理员 → Gateway → manage(/role/assign)
  │
  ├─→ [1] 校验管理员自身权限
  ├─→ [2] 创建/更新用户-角色绑定
  ├─→ [3] 重新计算用户权限（合并所有角色策略）
  ├─→ [4] 清除该用户权限缓存（Redis）
  └─→ [5] 返回分配成功
```

---

## 四、各服务 API 接口定义

### user 服务 API

```
POST   /user/create              创建用户
GET    /user/{id}                查询用户详情
GET    /user/by-username         按用户名查询（login 调用）
GET    /user/list                用户列表（分页）
PUT    /user/{id}                更新用户信息
DELETE /user/{id}                删除用户
PATCH  /user/{id}/status         启用/禁用账号
GET    /user/{id}/tags           查询用户标签
POST   /user/{id}/tags           设置用户标签
```

### login 服务 API

```
POST   /auth                     登录（编排：user→security→manage→签发token）
POST   /auth/refresh             刷新 Token
POST   /logout                   登出
GET    /session/list             当前用户会话列表
DELETE /session/{id}             强制下线指定会话
GET    /audit/login-log          登录审计日志
```

### security 服务 API

```
POST   /password/set             设置密码哈希（注册时调用）
POST   /password/verify          校验密码（login 调用）
POST   /password/change          修改密码（需旧密码验证）
PATCH  /password/reset           重置密码（管理员）
POST   /mfa/enable               启用 MFA（返回密钥+二维码）
POST   /mfa/verify               校验 MFA 码
POST   /mfa/disable              关闭 MFA
POST   /risk/evaluate            风控评估
GET    /risk/rules               风控规则列表
POST   /risk/rules               创建风控规则
POST   /bruteforce/check         暴力破解检查
GET    /blacklist                黑名单列表
POST   /blacklist                添加黑名单
DELETE /blacklist/{id}           移除黑名单
GET    /password-policy          密码策略查询
PUT    /password-policy          更新密码策略
GET    /security/events          安全事件日志
```

### manage 服务 API

```
POST   /role/create              创建角色
GET    /role/{id}                角色详情
GET    /role/list                角色列表
PUT    /role/{id}                更新角色
DELETE /role/{id}                删除角色
POST   /role/assign              分配角色给用户
DELETE /role/revoke              撤销用户角色
GET    /role/user/{user_id}      查询用户角色

POST   /policy/create            创建策略
GET    /policy/{id}              策略详情
GET    /policy/list              策略列表
PUT    /policy/{id}              更新策略
DELETE /policy/{id}              删除策略
POST   /policy/attach            绑定策略到角色
DELETE /policy/detach            解绑策略

GET    /permission/check         权限校验（user_id + resource + action）
GET    /permission/user          查询用户全部权限
GET    /permission/evaluate      权限评估（含条件判断）

GET    /config                   IAM 全局配置
PUT    /config                   更新 IAM 配置
```

---

## 五、服务间调用约定

### 调用方式
- HTTP REST（当前阶段）
- 未来可升级为 gRPC

### 调用鉴权
- 服务间调用使用 `X-Service-Token`（服务间共享密钥）
- Gateway 注入 `X-User-Id` Header 传递当前登录用户 ID

### 超时与重试

| 调用链 | 超时 | 重试 |
|--------|------|------|
| login → user | 3s | 1次 |
| login → security | 3s | 0次（密码校验不重试） |
| login → manage | 3s | 1次 |
| Gateway → 任意 | 5s | 0次 |

---

## 六、风险点与规避方案

### 风险1：login 依赖链过长，任一服务故障导致登录失败

**规避**：
- security 密码校验失败 = 立即返回，不继续调用
- manage 权限查询超时 → 返回最小权限集（降级）
- user 服务不可用 → 返回"服务暂不可用"（不缓存用户状态）
- 各服务健康检查独立，login 记录依赖状态

### 风险2：服务间调用形成级联故障

**规避**：
- 每个调用设置严格超时（3s）
- login 引入熔断器（Resilience4j CircuitBreaker）
- 调用失败记录审计日志，不静默吞错
- security 密码校验不重试（防暴力破解）

### 风险3：密码数据泄露

**规避**：
- 密码哈希仅存储在 security 服务数据库
- security 数据库独立，其他服务无访问权限
- 密码校验走 API，不在网络传输明文密码（HTTPS + 请求体）
- 密码策略强制 bcrypt/argon2，禁止 MD5/SHA

### 风险4：Token 被盗用

**规避**：
- Token 绑定 IP + User-Agent 指纹
- 会话记录存 Redis，支持强制下线
- Refresh Token 单次使用（用后失效）
- 敏感操作（改密码/删用户）强制二次验证

### 风险5：服务间调用被伪造

**规避**：
- 内网服务间调用使用 `X-Service-Token` 验证
- Gateway 注入的 `X-User-Id` 由 Gateway 签名，后端验签
- 服务间不允许绕过 Gateway 直接暴露给外部

### 风险6：循环依赖

**规避**：
- 架构设计强制单向依赖：login → user/security/manage
- user/security/manage 互不依赖
- 代码审查时检查 import 依赖图
- 未来引入 DDD 事件驱动进一步解耦

---

## 七、数据库分离方案

| 服务 | 数据库名 | 说明 |
|------|----------|------|
| user | `iam_user_db` | 用户档案 |
| login | `iam_login_db` | 会话 + 审计 |
| security | `iam_security_db` | 密码 + MFA + 风控 |
| manage | `iam_manage_db` | RBAC + 策略 |

每个服务的 `application.properties` 配置独立数据源，禁止跨库 JOIN。

---

## 八、缓存策略

| 数据 | 缓存位置 | TTL | 失效策略 |
|------|----------|-----|----------|
| 用户权限 | Redis | 5min | 权限变更时主动清除 |
| 会话 Token | Redis | = Token 过期时间 | 登出时删除 |
| 暴力破解计数 | Redis | 15min | 自动过期 |
| 密码策略 | Redis | 1h | 策略变更时主动清除 |
| 黑名单 | Redis | = 黑名单过期时间 | 添加/删除时同步 |
