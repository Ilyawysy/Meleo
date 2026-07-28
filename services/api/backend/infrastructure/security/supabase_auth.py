from __future__ import annotations

from typing import Any, Dict, List, Optional

import jwt
import httpx
from fastapi import HTTPException, status
from supabase import Client, create_client

from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger

logger = get_logger("supabase_auth")


class SupabaseAuthService:
    """Сервис для работы с Supabase Auth (JWT и Admin API)."""

    def __init__(self) -> None:
        if not settings.SUPABASE_URL:
            raise ValueError("SUPABASE_URL is not configured.")
        if not settings.SUPABASE_SERVICE_ROLE_KEY:
            raise ValueError("SUPABASE_SERVICE_ROLE_KEY is not configured.")

        self._supabase_url = settings.SUPABASE_URL.rstrip("/")
        self._service_role_key = settings.SUPABASE_SERVICE_ROLE_KEY
        self._jwt_secret = settings.SUPABASE_JWT_SECRET
        self._jwks_url = f"{self._supabase_url}/auth/v1/.well-known/jwks.json"
        self._jwks_client: jwt.PyJWKClient | None = None
        self._client: Client = create_client(self._supabase_url, self._service_role_key)
        self._anon_client: Client | None = None
        if settings.SUPABASE_ANON_KEY:
            self._anon_client = create_client(self._supabase_url, settings.SUPABASE_ANON_KEY)
        self._admin_base_url = f"{self._supabase_url}/auth/v1/admin"
        self._timeout = float(getattr(settings, "REQUEST_TIMEOUT_S", 10))

    def _admin_headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self._service_role_key}",
            "apikey": self._service_role_key,
            "Content-Type": "application/json",
        }

    def _auth_headers(self, access_token: str) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {access_token}",
            "apikey": self._service_role_key,
            "Content-Type": "application/json",
        }

    def _auth_request(
        self, method: str, path: str, access_token: str, **kwargs: Any
    ) -> Dict[str, Any]:
        url = f"{self._supabase_url}{path}"
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.request(
                    method,
                    url,
                    headers=self._auth_headers(access_token),
                    **kwargs,
                )
            response.raise_for_status()
            if response.content:
                return response.json()
            return {}
        except httpx.HTTPStatusError as e:
            logger.warning(
                "supabase_auth_request_failed",
                status_code=e.response.status_code,
                response_text=e.response.text[:200],
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY, detail="Supabase Auth API error"
            )
        except httpx.RequestError as e:
            logger.error("supabase_auth_request_error", error=str(e))
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase unavailable"
            )

    def _admin_request(self, method: str, path: str, **kwargs: Any) -> Dict[str, Any]:
        url = f"{self._admin_base_url}{path}"
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.request(method, url, headers=self._admin_headers(), **kwargs)
            response.raise_for_status()
            if response.content:
                return response.json()
            return {}
        except httpx.HTTPStatusError as e:
            logger.warning(
                "supabase_admin_request_failed",
                status_code=e.response.status_code,
                response_text=e.response.text[:200],
            )
            if e.response.status_code == 404:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
            if e.response.status_code == 409:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT, detail="User already exists"
                )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY, detail="Supabase Admin API error"
            )
        except httpx.RequestError as e:
            logger.error("supabase_admin_request_error", error=str(e))
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase unavailable"
            )

    def _extract_user_id(self, payload: Any) -> Optional[str]:
        if isinstance(payload, dict):
            user_id = payload.get("id")
            if user_id:
                return str(user_id)
            user = payload.get("user")
            if isinstance(user, dict) and user.get("id"):
                return str(user.get("id"))
        user_obj = getattr(payload, "user", None)
        if user_obj and getattr(user_obj, "id", None):
            return str(user_obj.id)
        return None

    def _object_to_dict(self, payload: Any) -> Dict[str, Any]:
        if isinstance(payload, dict):
            return payload
        if payload is None:
            return {}
        if hasattr(payload, "model_dump"):
            return payload.model_dump()
        if hasattr(payload, "dict"):
            return payload.dict()
        if hasattr(payload, "__dict__"):
            return dict(payload.__dict__)
        return {}

    def _normalize_user_payload(self, payload: Any) -> Dict[str, Any]:
        if (
            isinstance(payload, dict)
            and "user" in payload
            and isinstance(payload.get("user"), dict)
        ):
            return payload["user"]
        user_obj = getattr(payload, "user", None)
        if user_obj is not None:
            return self._object_to_dict(user_obj)
        return self._object_to_dict(payload)

    def _admin_client(self) -> Any:
        return getattr(self._client.auth, "admin", None)

    def verify_token(self, token: str) -> Dict[str, Any]:
        """Проверяет JWT токен Supabase (HS256 legacy или ES256/RS256 через JWKS)."""
        try:
            unverified_header = jwt.get_unverified_header(token)
            alg = unverified_header.get("alg")
            if not alg:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
                )

            if alg == "HS256":
                if not self._jwt_secret:
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail="SUPABASE_JWT_SECRET is not configured",
                    )
                payload = jwt.decode(
                    token,
                    self._jwt_secret,
                    algorithms=["HS256"],
                    audience="authenticated",
                    leeway=30,
                    issuer=f"{self._supabase_url}/auth/v1",
                )
            elif alg in {"RS256", "ES256"}:
                if self._jwks_client is None:
                    self._jwks_client = jwt.PyJWKClient(self._jwks_url)
                signing_key = self._jwks_client.get_signing_key_from_jwt(token)
                payload = jwt.decode(
                    token,
                    signing_key.key,
                    algorithms=[alg],
                    audience="authenticated",
                    leeway=30,
                    issuer=f"{self._supabase_url}/auth/v1",
                )
            else:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
                )
            return payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has expired"
            )
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    def create_user(self, email: str, password: str, email_confirmed: bool = True) -> str:
        """Создать пользователя в Supabase Auth и вернуть UUID."""
        admin = self._admin_client()
        payload = {"email": email, "password": password, "email_confirm": email_confirmed}
        if admin and hasattr(admin, "create_user"):
            user_data = admin.create_user(payload)
        else:
            user_data = self._admin_request("POST", "/users", json=payload)
        user_id = self._extract_user_id(user_data)
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Supabase user created but ID not found",
            )
        return user_id

    def sign_up_user(self, email: str, password: str) -> Dict[str, Any]:
        """
        Публичная регистрация пользователя через Supabase (отправляет OTP).

        Возвращает dict со следующими полями:
            id: str — UUID пользователя в Supabase
            email_confirmed: bool — True, если email уже был подтверждён ранее
            identities_empty: bool — True, если Supabase вернул "фейкового" юзера
                                     (email уже занят с другим паролем; в этом
                                     случае письмо НЕ отправляется)
        """
        if not self._anon_client or not hasattr(self._anon_client.auth, "sign_up"):
            logger.warning("supabase_anon_client_unavailable_falling_back_to_admin")
            user_id = self.create_user(email, password, email_confirmed=False)
            return {"id": user_id, "email_confirmed": False, "identities_empty": False}

        user_data = self._anon_client.auth.sign_up({"email": email, "password": password})
        user_id = self._extract_user_id(user_data)
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Supabase sign up succeeded but ID not found",
            )

        user_dict = self._normalize_user_payload(user_data)
        email_confirmed = bool(
            user_dict.get("email_confirmed_at") or user_dict.get("confirmed_at")
        )
        identities = user_dict.get("identities")
        identities_empty = isinstance(identities, list) and len(identities) == 0

        return {
            "id": user_id,
            "email_confirmed": email_confirmed,
            "identities_empty": identities_empty,
        }

    def sign_out(self, access_token: str) -> None:
        """Logout по access token (Supabase /auth/v1/logout)."""
        try:
            self._auth_request("POST", "/auth/v1/logout", access_token)
        except HTTPException as e:
            if e.status_code == status.HTTP_404_NOT_FOUND:
                return
            raise

    def list_users(self, page: int = 1, per_page: int = 20) -> Dict[str, Any]:
        admin = self._admin_client()
        if admin and hasattr(admin, "list_users"):
            payload = admin.list_users(page=page, per_page=per_page)
            users = getattr(payload, "users", None)
            if users is not None:
                return {
                    "users": [self._object_to_dict(user) for user in users],
                    "next_page": getattr(payload, "next_page", None),
                    "total": getattr(payload, "total", None),
                }
            return self._object_to_dict(payload)
        return self._admin_request("GET", "/users", params={"page": page, "per_page": per_page})

    def find_user_by_email(
        self, email: str, max_pages: int = 10, per_page: int = 100
    ) -> Optional[Dict[str, Any]]:
        admin = self._admin_client()
        if admin and hasattr(admin, "get_user_by_email"):
            user_data = admin.get_user_by_email(email)
            normalized = self._normalize_user_payload(user_data)
            return normalized if normalized else None
        for page in range(1, max_pages + 1):
            payload = self.list_users(page=page, per_page=per_page)
            users = payload.get("users") or payload.get("items") or []
            for user in users:
                if isinstance(user, dict) and user.get("email") == email:
                    return user
            if len(users) < per_page:
                break
        return None

    def get_user(self, user_id: str) -> Dict[str, Any]:
        admin = self._admin_client()
        if admin and hasattr(admin, "get_user_by_id"):
            return self._normalize_user_payload(admin.get_user_by_id(user_id))
        if admin and hasattr(admin, "get_user"):
            return self._normalize_user_payload(admin.get_user(user_id))
        return self._admin_request("GET", f"/users/{user_id}")

    def update_user(self, user_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        admin = self._admin_client()
        if admin and hasattr(admin, "update_user_by_id"):
            return self._normalize_user_payload(admin.update_user_by_id(user_id, data))
        if admin and hasattr(admin, "update_user"):
            return self._normalize_user_payload(admin.update_user(user_id, data))
        return self._admin_request("PUT", f"/users/{user_id}", json=data)

    def delete_user(self, user_id: str) -> None:
        self._admin_request("DELETE", f"/users/{user_id}")

    def ban_user(self, user_id: str, duration: str = "8760h") -> None:
        self.update_user(user_id, {"ban_duration": duration})

    def unban_user(self, user_id: str) -> None:
        self.update_user(user_id, {"ban_duration": "none"})

    def get_user_roles(self, user_id: str) -> List[str]:
        user_data = self.get_user(user_id)
        app_metadata = user_data.get("app_metadata") or {}
        roles = app_metadata.get("roles")
        if isinstance(roles, list):
            return [role for role in roles if isinstance(role, str)]
        role = user_data.get("role")
        return [role] if isinstance(role, str) else []

    def assign_role(self, user_id: str, role: str) -> None:
        user_data = self.get_user(user_id)
        app_metadata = user_data.get("app_metadata") or {}
        roles = app_metadata.get("roles")
        if not isinstance(roles, list):
            roles = []
        if role not in roles:
            roles.append(role)
        self.update_user(user_id, {"app_metadata": {**app_metadata, "roles": roles}})

    def remove_role(self, user_id: str, role: str) -> None:
        user_data = self.get_user(user_id)
        app_metadata = user_data.get("app_metadata") or {}
        roles = app_metadata.get("roles")
        if not isinstance(roles, list):
            return
        roles = [item for item in roles if item != role]
        self.update_user(user_id, {"app_metadata": {**app_metadata, "roles": roles}})


_supabase_auth_service: Optional[SupabaseAuthService] = None


def get_supabase_auth_service() -> SupabaseAuthService:
    global _supabase_auth_service
    if _supabase_auth_service is None:
        _supabase_auth_service = SupabaseAuthService()
    return _supabase_auth_service
