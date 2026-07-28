from __future__ import annotations

from typing import Any, Dict


def mask_sensitive_fields(data: Dict[str, Any], fields_to_mask: list[str] = None) -> Dict[str, Any]:
    """
    Маскирует чувствительные поля в словаре для безопасного логирования

    Args:
            data: Словарь с данными
            fields_to_mask: Список полей для маскировки (по умолчанию: password, client_secret)

    Returns:
            Новый словарь с замаскированными полями
    """
    if fields_to_mask is None:
        fields_to_mask = ["password", "client_secret", "refresh_token", "email"]

    masked = data.copy()
    for field in fields_to_mask:
        if field in masked:
            masked[field] = "***"

    return masked
