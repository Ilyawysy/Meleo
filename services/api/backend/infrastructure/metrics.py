from __future__ import annotations

import time

from fastapi import Request, Response
from prometheus_client import Counter, Histogram

_UNMATCHED_ROUTE = "__unmatched__"

http_requests_total = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "route", "status"],
)

http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 30.0],
)

db_query_duration_seconds = Histogram(
    "db_query_duration_seconds",
    "Individual DB query latency",
    ["op", "entity"],
    buckets=[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)

db_queries_total = Counter(
    "db_queries_total",
    "Total DB queries",
    ["op", "entity"],
)


async def metrics_middleware(request: Request, call_next):
    """Prometheus metrics middleware using route templates (not raw paths)."""
    start = time.perf_counter()
    response: Response = await call_next(request)
    duration = time.perf_counter() - start

    # Use route template (e.g. "/tasks/{task_id}") instead of raw path
    route_obj = request.scope.get("route")
    if route_obj and hasattr(route_obj, "path"):
        route = route_obj.path
    else:
        route = _UNMATCHED_ROUTE

    http_requests_total.labels(
        method=request.method,
        route=route,
        status=response.status_code,
    ).inc()

    http_request_duration_seconds.labels(method=request.method, route=route).observe(duration)

    return response
