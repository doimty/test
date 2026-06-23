# API Hub Sign-in Runner

本项目是一个 cron 友好的多站点签到脚本，用来把 All API Hub / New API 类账号的每日签到从浏览器扩展迁移到本地定时任务。

设计目标很简单：

- 凭据不写进仓库。
- JSON 配置只保存站点、账号名和环境变量名。
- token、cookie、密码只从 `.env` 读取。
- 对 Turnstile、Captcha、WAF、签名请求头这类浏览器验证直接跳过，不把它们伪装成成功。
- 单个站点失败不影响其它站点的结果汇总。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `api_hub_signin.py` | 主 runner，按配置逐个账号签到。 |
| `routerteam_signin_cron.sh` | cron / OpenClaw scheduler 调用入口。 |
| `import_all_api_hub_backup.py` | 从 All API Hub 导出的备份 JSON 生成本地配置和 env。 |
| `examples/api_hub_signin.example.json` | 脱敏配置示例。 |
| `examples/api_hub_signin.env.example` | 脱敏 env 示例。 |

不要提交真实的：

- `api_hub_signin.env`
- `api_hub_signin.json`
- `api_hub_signin_import_report.json`
- `logs/`
- 任何包含 token、cookie、密码、导出备份的文件

## 支持的 provider

### `new-api`

适合大部分 New API / Veloera / VoAPI / Rix API / Neo API 变体。

请求会自动带上 Bearer token，并补充兼容用户 ID 头：

- `New-API-User`
- `Veloera-User`
- `X-Api-User`
- `voapi-user`
- `User-id`
- `Rix-Api-User`
- `neo-api-user`

默认签到接口：

```text
POST /api/user/checkin
```

### `routerteam`

RouterTeam 专用流程：

1. `POST /api/auth/login`
2. `GET /api/user/reward-center`
3. `POST /api/user/reward-center/sign-in`

账号密码从 env 读取。

### `anyrouter`

AnyRouter 类站点，使用 cookie auth。

默认签到接口：

```text
POST /api/user/sign_in
```

### `http`

通用单接口签到。适合明确知道一个 GET/POST 接口就能完成签到的站点。

## 快速开始

复制示例文件：

```bash
cp examples/api_hub_signin.example.json api_hub_signin.json
cp examples/api_hub_signin.env.example api_hub_signin.env
chmod 600 api_hub_signin.env
```

编辑 `api_hub_signin.env`，填入真实凭据。

语法检查：

```bash
python3 -m py_compile api_hub_signin.py import_all_api_hub_backup.py
bash -n routerteam_signin_cron.sh
```

单账号试跑：

```bash
set -a
source ./api_hub_signin.env
set +a
./api_hub_signin.py --config ./api_hub_signin.json --only routerteam --retries 0 --account-delay 0
```

全量试跑，不重试：

```bash
set -a
source ./api_hub_signin.env
set +a
./api_hub_signin.py --config ./api_hub_signin.json --retries 0 --account-delay 0.2
```

## OpenClaw scheduler 用法

本仓库提供的 `routerteam_signin_cron.sh` 是稳定入口。定时任务只需要调用这个 wrapper，不需要把 token 放进命令行。

示例：

```bash
./routerteam_signin_cron.sh
```

wrapper 默认读取当前目录下的：

- `api_hub_signin.env`
- `api_hub_signin.json`

也可以用环境变量覆盖：

```bash
API_HUB_SIGNIN_ENV=/path/to/api_hub_signin.env \
API_HUB_SIGNIN_CONFIG=/path/to/api_hub_signin.json \
./routerteam_signin_cron.sh
```

## 从 All API Hub 备份导入

```bash
./import_all_api_hub_backup.py all-api-hub-backup.json \
  --config-out ./api_hub_signin.json \
  --env-out ./api_hub_signin.env \
  --report-out ./api_hub_signin_import_report.json
chmod 600 ./api_hub_signin.env ./api_hub_signin.json ./api_hub_signin_import_report.json
```

导入策略是保守的，只自动导入：

- `autoCheckInEnabled === true`
- 未禁用账号
- 健康状态为 `healthy`
- `site_type === "new-api"`
- `authType === "access_token"`
- 没有自定义外部签到 URL

外部签到页、Turnstile、Cloudflare、WAF、滑块等浏览器验证站点不适合直接 cron 化，应该保持禁用或单独适配。

## 结果语义

runner 输出四类状态：

| 状态 | 含义 |
| --- | --- |
| `success` | 本次执行完成签到。 |
| `already_checked` | 今天已经签到过。 |
| `skipped` | 本地禁用、站点不允许签到、需要浏览器验证等。 |
| `failed` | 网络、接口、认证或未知错误。 |

汇总示例：

```text
summary total=24 success=0 already_checked=24 skipped=0 failed=0
```

## 安全原则

- 不要把 token、cookie、密码放在命令行参数里。
- 不要提交真实 env、真实配置、日志或备份 JSON。
- 公开仓库只保留脚本和脱敏 example。
- 失败日志会自动遮蔽常见 token 字段，但不要依赖日志脱敏来保护秘密。
