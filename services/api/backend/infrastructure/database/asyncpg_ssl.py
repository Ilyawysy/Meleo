"""Single place for asyncpg SSL context. No CA → fail fast with clear error."""
from __future__ import annotations

import os
import ssl
from pathlib import Path


def build_asyncpg_ssl() -> ssl.SSLContext | None:
	# Explicit disable (local only)
	if os.getenv("DB_SSL_DISABLE", "").lower() in ("1", "true", "yes"):
		return None

	cafile = os.getenv("PG_SSLROOTCERT")
	if not cafile:
		raise RuntimeError(
			"No CA file configured. Set PG_SSLROOTCERT to Supabase prod-ca-2021.crt"
		)

	p = Path(cafile)
	if not p.is_absolute():
		# repo-relative: this file is backend/infrastructure/database/asyncpg_ssl.py
		project_root = Path(__file__).resolve().parents[3]
		p = project_root / p
	if not p.exists():
		raise FileNotFoundError(f"CA file not found: {p}")

	# Never allow this in prod
	if os.getenv("DB_SSL_ALLOW_SELF_SIGNED", "").lower() in ("1", "true", "yes"):
		raise RuntimeError("DB_SSL_ALLOW_SELF_SIGNED must not be enabled")

	ctx = ssl.create_default_context(cafile=str(p))
	# Python 3.13 enables VERIFY_X509_STRICT by default and it can reject some CA certs.
	if hasattr(ssl, "VERIFY_X509_STRICT"):
		ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
	return ctx
