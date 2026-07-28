from __future__ import annotations

import asyncio
from typing import Any

import httpx


async def obtain_token(
    supabase_url: str,
    anon_key: str,
    email: str,
    password: str,
) -> str:
    """Log in via Supabase Auth REST API and return the access_token (JWT)."""
    url = f"{supabase_url.rstrip('/')}/auth/v1/token?grant_type=password"
    headers = {"apikey": anon_key, "Content-Type": "application/json"}
    body = {"email": email, "password": password}
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(url, json=body, headers=headers)
    if resp.status_code != 200:
        raise RuntimeError(f"Supabase login failed ({resp.status_code}): {resp.text}")
    data = resp.json()
    token = data.get("access_token")
    if not token:
        raise RuntimeError(f"No access_token in Supabase response: {data}")
    return token


class AgentClient:
    def __init__(self, base_url: str, token: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = token

    def _headers(self, token_override: str | None = None) -> dict[str, str]:
        tok = token_override if token_override is not None else self._token
        return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}

    def _build_body(
        self,
        history: list[dict[str, Any]],
        mentions: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        return {
            "session_id": None,
            "user_id": None,
            "request_id": None,
            "history": history,
            "user_token": None,
            "content_display": None,
            "mentions": mentions,
        }

    async def raw_submit(
        self,
        history: list[dict[str, Any]],
        token_override: str | None = None,
    ) -> httpx.Response:
        url = f"{self._base_url}/api/v1/agent/chat.run"
        body = self._build_body(history)
        async with httpx.AsyncClient(timeout=30.0) as client:
            return await client.post(url, json=body, headers=self._headers(token_override))

    async def submit(
        self,
        history: list[dict[str, Any]],
        mentions: list[dict[str, Any]] | None = None,
    ) -> str:
        url = f"{self._base_url}/api/v1/agent/chat.run"
        body = self._build_body(history, mentions)
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(url, json=body, headers=self._headers())
        if response.status_code != 202:
            raise RuntimeError(f"chat.run returned {response.status_code}: {response.text}")
        data = response.json()
        return data["job_id"]

    async def poll(
        self,
        job_id: str,
        timeout: float = 120.0,
        interval: float = 2.0,
    ) -> dict[str, Any]:
        url = f"{self._base_url}/api/v1/agent/jobs/{job_id}"
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        async with httpx.AsyncClient(timeout=30.0) as client:
            while True:
                response = await client.get(url, headers=self._headers())
                response.raise_for_status()
                data: dict[str, Any] = response.json()
                status = data.get("status")
                if status in ("completed", "failed"):
                    return data
                if loop.time() >= deadline:
                    raise TimeoutError(f"Job {job_id} did not complete within {timeout}s")
                await asyncio.sleep(interval)

    async def run(
        self,
        history: list[dict[str, Any]],
        mentions: list[dict[str, Any]] | None = None,
        timeout: float = 120.0,
        interval: float = 2.0,
    ) -> dict[str, Any]:
        job_id = await self.submit(history, mentions)
        return await self.poll(job_id, timeout=timeout, interval=interval)
