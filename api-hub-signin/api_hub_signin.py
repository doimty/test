#!/usr/bin/env python3
"""Multi-account API-site sign-in runner.

This is a local cron-friendly adapter inspired by all-api-hub's provider model:
- one account entry per site
- one provider implementation per site family
- credentials are read from environment variables only

Config file default: /root/.openclaw/workspace/api_hub_signin.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

DEFAULT_CONFIG = os.environ.get("API_HUB_SIGNIN_CONFIG", "./api_hub_signin.json")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
ALREADY_CHECKED_SNIPPETS = ("今天已经签到", "已经签到", "已签到", "already")
SUCCESS_SNIPPETS = ("success", "签到成功", "成功")
BOT_CHALLENGE_SNIPPETS = (
    "turnstile",
    "cf-turnstile",
    "captcha",
    "aliyun_waf",
    "aliyuncaptcha",
    "访问验证",
    "滑动验证",
    "为了更好的访问体验，请进行验证",
    "验证码",
    "人机验证",
    "token 为空",
    "game_integrity",
    "完整性标记",
    "签名请求头",
)
NO_CHECKIN_SNIPPETS = (
    "签到功能未启用",
    "checkin disabled",
    "check-in disabled",
)
COMPAT_USER_ID_HEADER_NAMES = (
    "New-API-User",
    "Veloera-User",
    "X-Api-User",
    "voapi-user",
    "User-id",
    "Rix-Api-User",
    "neo-api-user",
)


def build_compat_user_id_headers(user_id: int | str | None) -> dict[str, str]:
    if not user_id:
        return {}
    value = str(user_id)
    return {name: value for name in COMPAT_USER_ID_HEADER_NAMES}


@dataclass
class Result:
    account: str
    status: str
    message: str = ""

    @property
    def ok(self) -> bool:
        return self.status in {"success", "already_checked", "skipped"}

    def line(self) -> str:
        suffix = f" message={self.message}" if self.message else ""
        return f"account={self.account} status={self.status}{suffix}"


class SigninError(Exception):
    pass


class HttpClient:
    def __init__(self, base_url: str, secrets: list[str] | None = None, timeout: int = 45):
        self.base_url = base_url.rstrip("/")
        self.secrets = [s for s in (secrets or []) if s]
        self.timeout = timeout

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        cookie: str | None = None,
        user_id: int | str | None = None,
        payload: Any | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, Any]:
        url = path if path.startswith("http://") or path.startswith("https://") else self.base_url + path
        req_headers = {
            "User-Agent": UA,
            "Accept": "application/json, text/plain, */*",
            "Origin": self.base_url,
            "Referer": self.base_url + "/",
        }
        if headers:
            req_headers.update(headers)
        req_headers.update(build_compat_user_id_headers(user_id))
        data = None
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            req_headers.setdefault("Content-Type", "application/json")
        if token:
            req_headers["Authorization"] = "Bearer " + token
        if cookie:
            req_headers["Cookie"] = cookie
        req = urllib.request.Request(url, data=data, headers=req_headers, method=method.upper())
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return resp.status, self._parse_body(resp.read())
        except urllib.error.HTTPError as exc:
            return exc.code, self._parse_body(exc.read())
        except urllib.error.URLError as exc:
            raise SigninError(f"network_error {exc.reason}") from exc
        except TimeoutError as exc:
            raise SigninError("timeout") from exc

    @staticmethod
    def _parse_body(raw_bytes: bytes) -> Any:
        raw = raw_bytes.decode("utf-8", "replace")
        if not raw:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw

    def safe_body(self, body: Any, limit: int = 800) -> str:
        text = json.dumps(body, ensure_ascii=False) if isinstance(body, (dict, list)) else str(body)
        for secret in self.secrets:
            if len(secret) >= 4:
                text = text.replace(secret, "***")
        text = re.sub(r'("accessToken"\s*:\s*")[^"]+', r"\1***", text)
        text = re.sub(r'("token"\s*:\s*")[^"]+', r"\1***", text)
        text = re.sub(r"Bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer ***", text)
        text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "***jwt***", text)
        return text[:limit]


def env_required(name: str | None, label: str) -> str:
    if not name:
        raise SigninError(f"missing_config {label}_env")
    value = os.environ.get(name)
    if not value:
        raise SigninError(f"missing_env {name}")
    return value


def is_already_checked(message: str) -> bool:
    lower = message.lower()
    return any(s.lower() in lower for s in ALREADY_CHECKED_SNIPPETS)


def is_success_message(message: str) -> bool:
    lower = message.lower()
    return any(s.lower() in lower for s in SUCCESS_SNIPPETS)


def is_bot_challenge(message: str) -> bool:
    lower = message.lower()
    return any(s.lower() in lower for s in BOT_CHALLENGE_SNIPPETS)


def is_no_checkin(message: str) -> bool:
    lower = message.lower()
    return any(s.lower() in lower for s in NO_CHECKIN_SNIPPETS)


def summarize_routerteam_sign(sign: dict[str, Any]) -> str:
    keys = [
        "signedInToday",
        "canSignIn",
        "todayReward",
        "totalReward",
        "monthSignedDays",
        "wechatRequired",
        "wechatBound",
    ]
    parts = [f"{key}={sign.get(key)!r}" for key in keys if key in sign]
    blocked = sign.get("blockedMessage")
    if blocked:
        parts.append(f"blockedMessage={blocked!r}")
    return " ".join(parts)


def routerteam_provider(account: dict[str, Any]) -> Result:
    name = account["name"]
    username = env_required(account.get("username_env"), "username")
    password = env_required(account.get("password_env"), "password")
    client = HttpClient(account["base_url"], secrets=[username, password])

    status, body = client.request(
        "POST",
        "/api/auth/login",
        payload={"username": username, "password": password},
        headers={"Referer": client.base_url + "/console/invite-rewards"},
    )
    if not 200 <= status < 300:
        return Result(name, "failed", f"login_failed http={status} body={client.safe_body(body)}")
    token = body.get("accessToken") if isinstance(body, dict) else None
    if not token:
        return Result(name, "failed", f"login_no_token http={status} body={client.safe_body(body)}")

    status, body = client.request(
        "GET",
        "/api/user/reward-center",
        token=token,
        headers={"Referer": client.base_url + "/console/invite-rewards"},
    )
    if not 200 <= status < 300:
        return Result(name, "failed", f"reward_center_failed http={status} body={client.safe_body(body)}")
    sign = body.get("signIn") if isinstance(body, dict) else None
    if not isinstance(sign, dict):
        return Result(name, "failed", f"reward_center_no_signin http={status} body={client.safe_body(body)}")

    before = summarize_routerteam_sign(sign)
    if sign.get("signedInToday") is True:
        return Result(name, "already_checked", before)
    if sign.get("canSignIn") is not True:
        msg = sign.get("blockedMessage") or sign.get("message") or "cannot_sign_in_now"
        return Result(name, "skipped", f"{before} {msg}")

    status, body = client.request(
        "POST",
        "/api/user/reward-center/sign-in",
        token=token,
        headers={"Referer": client.base_url + "/console/invite-rewards"},
    )
    if not 200 <= status < 300:
        return Result(name, "failed", f"sign_in_failed http={status} body={client.safe_body(body)}")
    result = body.get("data") if isinstance(body, dict) and isinstance(body.get("data"), dict) else body
    message = result.get("message") if isinstance(result, dict) else ""
    new_sign = result.get("signIn") if isinstance(result, dict) else None
    suffix = f" after={summarize_routerteam_sign(new_sign)}" if isinstance(new_sign, dict) else ""
    return Result(name, "success", f"{message or '-'}{suffix}")


def new_api_provider(account: dict[str, Any]) -> Result:
    """Basic New-API-family check-in.

    Works for sites where Access Token check-in is enough.
    Browser-only Turnstile handling is intentionally not attempted here.
    """
    name = account["name"]
    token = env_required(account.get("token_env") or account.get("access_token_env"), "token")
    client = HttpClient(account["base_url"], secrets=[token])
    endpoint = account.get("checkin_path") or "/api/user/checkin"
    status, body = client.request(
        "POST",
        endpoint,
        token=token,
        user_id=account.get("user_id"),
        payload={},
    )
    message = ""
    success = False
    if isinstance(body, dict):
        message = str(body.get("message") or body.get("msg") or "")
        success = bool(body.get("success") is True or body.get("code") in (0, 200))
    else:
        message = str(body or "")
    body_text = client.safe_body(body)
    if is_bot_challenge(message) or is_bot_challenge(body_text):
        return Result(name, "skipped", f"browser_challenge_required http={status} body={body_text}")
    if is_no_checkin(message) or is_no_checkin(body_text):
        return Result(name, "skipped", f"checkin_disabled http={status} body={body_text}")
    if is_already_checked(message):
        return Result(name, "already_checked", message)
    if 200 <= status < 300 and (success or is_success_message(message)):
        return Result(name, "success", message or "checkin_ok")
    if status == 404:
        return Result(name, "failed", "endpoint_not_supported /api/user/checkin")
    return Result(name, "failed", f"http={status} body={body_text}")


def anyrouter_provider(account: dict[str, Any]) -> Result:
    """AnyRouter-family check-in using cookie auth.

    Needs a valid session cookie. If the site has extra bot checks, it may still
    need browser/manual handling.
    """
    name = account["name"]
    cookie = env_required(account.get("cookie_env"), "cookie")
    client = HttpClient(account["base_url"], secrets=[cookie])
    endpoint = account.get("checkin_path") or "/api/user/sign_in"
    status, body = client.request(
        "POST",
        endpoint,
        cookie=cookie,
        user_id=account.get("user_id"),
        payload={},
        headers={"X-Requested-With": "XMLHttpRequest"},
    )
    message = ""
    success = False
    if isinstance(body, dict):
        message = str(body.get("message") or body.get("msg") or "")
        success = bool(body.get("success") is True or body.get("code") in (0, 200) or body.get("ret") in (0, 200))
    else:
        message = str(body or "")
    body_text = client.safe_body(body)
    if is_bot_challenge(message) or is_bot_challenge(body_text):
        return Result(name, "skipped", f"browser_challenge_required http={status} body={body_text}")
    if is_no_checkin(message) or is_no_checkin(body_text):
        return Result(name, "skipped", f"checkin_disabled http={status} body={body_text}")
    if 200 <= status < 300 and (success or is_success_message(message)):
        return Result(name, "success", message or "checkin_ok")
    # AnyRouter can return an empty success message for already checked in some deployments.
    if is_already_checked(message):
        return Result(name, "already_checked", message or "already_checked")
    return Result(name, "failed", f"http={status} body={body_text}")


def http_provider(account: dict[str, Any]) -> Result:
    """Simple configurable HTTP check-in provider.

    Use for sites where one GET/POST endpoint is enough.
    """
    name = account["name"]
    token = os.environ.get(account.get("token_env", "")) if account.get("token_env") else None
    cookie = os.environ.get(account.get("cookie_env", "")) if account.get("cookie_env") else None
    client = HttpClient(account["base_url"], secrets=[token or "", cookie or ""])
    payload = account.get("payload", {}) if account.get("method", "POST").upper() != "GET" else None
    headers = dict(account.get("headers") or {})
    status, body = client.request(
        account.get("method", "POST"),
        account["path"],
        token=token,
        cookie=cookie,
        user_id=account.get("user_id"),
        payload=payload,
        headers=headers,
    )
    text = client.safe_body(body)
    if status < 200 or status >= 300:
        return Result(name, "failed", f"http={status} body={text}")
    already = account.get("already_contains") or list(ALREADY_CHECKED_SNIPPETS)
    success = account.get("success_contains") or list(SUCCESS_SNIPPETS)
    raw = json.dumps(body, ensure_ascii=False) if isinstance(body, (dict, list)) else str(body)
    if any(str(s).lower() in raw.lower() for s in already):
        return Result(name, "already_checked", text)
    if any(str(s).lower() in raw.lower() for s in success):
        return Result(name, "success", text)
    return Result(name, "success", text)


PROVIDERS = {
    "routerteam": routerteam_provider,
    "new-api": new_api_provider,
    "newapi": new_api_provider,
    "anyrouter": anyrouter_provider,
    "http": http_provider,
}


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def run_account(account: dict[str, Any]) -> Result:
    name = account.get("name") or account.get("base_url") or "unnamed"
    if account.get("enabled") is False:
        return Result(name, "skipped", "disabled")
    provider_name = str(account.get("type") or "").lower()
    provider = PROVIDERS.get(provider_name)
    if not provider:
        return Result(name, "failed", f"unknown_provider {provider_name}")
    try:
        return provider(account)
    except SigninError as exc:
        return Result(name, "failed", str(exc))
    except Exception as exc:  # Keep one bad account from hiding the summary.
        return Result(name, "failed", f"unexpected_error {type(exc).__name__}: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run configured API-site sign-ins")
    parser.add_argument("--config", default=os.environ.get("API_HUB_SIGNIN_CONFIG", DEFAULT_CONFIG))
    parser.add_argument("--retries", type=int, default=int(os.environ.get("API_HUB_SIGNIN_RETRIES", "2")))
    parser.add_argument("--retry-delay", type=int, default=int(os.environ.get("API_HUB_SIGNIN_RETRY_DELAY", "8")))
    parser.add_argument(
        "--account-delay",
        type=float,
        default=float(os.environ.get("API_HUB_SIGNIN_ACCOUNT_DELAY", "0.25")),
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Run only matching account name, base_url, or source_account_id. Can be repeated.",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    accounts = config.get("accounts") or []
    if args.only:
        wanted = set(args.only)
        accounts = [
            account
            for account in accounts
            if account.get("name") in wanted
            or account.get("base_url") in wanted
            or account.get("source_account_id") in wanted
        ]
    if not isinstance(accounts, list) or not accounts:
        print("no_accounts_configured")
        return 2

    final_results: list[Result] = []
    for index, account in enumerate(accounts):
        name = account.get("name") or account.get("base_url") or "unnamed"
        result = Result(name, "failed", "not_run")
        attempts = max(1, args.retries + 1)
        for attempt in range(1, attempts + 1):
            result = run_account(account)
            print(f"attempt={attempt} {result.line()}")
            if result.ok:
                break
            if attempt < attempts:
                time.sleep(args.retry_delay)
        final_results.append(result)
        if index + 1 < len(accounts) and args.account_delay > 0:
            time.sleep(args.account_delay)

    success_count = sum(1 for r in final_results if r.status == "success")
    already_count = sum(1 for r in final_results if r.status == "already_checked")
    skipped_count = sum(1 for r in final_results if r.status == "skipped")
    failed = [r for r in final_results if r.status == "failed"]
    print(
        "summary "
        f"total={len(final_results)} "
        f"success={success_count} "
        f"already_checked={already_count} "
        f"skipped={skipped_count} "
        f"failed={len(failed)}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
