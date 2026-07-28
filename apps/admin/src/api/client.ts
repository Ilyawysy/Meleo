const BASE_URL = import.meta.env.VITE_API_BASE_URL || "";

async function request<T>(
  path: string,
  token: string,
  options?: RequestInit
): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...options?.headers,
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status}: ${text}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  getOverview: (token: string) =>
    request<OverviewData>("/api/v1/admin/analytics/overview", token),
  getTasks: (token: string, days = 30) =>
    request<TasksData>(`/api/v1/admin/analytics/tasks?days=${days}`, token),
  getFocus: (token: string, days = 30) =>
    request<FocusData>(`/api/v1/admin/analytics/focus?days=${days}`, token),
  getGamification: (token: string) =>
    request<GamificationData>("/api/v1/admin/analytics/gamification", token),
  getRetention: (token: string) =>
    request<RetentionRow[]>("/api/v1/admin/analytics/retention", token),
  postHogQuery: (token: string, query: string) =>
    request<PostHogResult>("/api/v1/admin/posthog/query", token, {
      method: "POST",
      body: JSON.stringify({ query }),
    }),
};

// Types
export interface OverviewData {
  total_users: number;
  active_today: number;
  active_week: number;
  active_month: number;
  new_today: number;
  new_week: number;
}

export interface TasksData {
  days: number;
  created_in_period: number;
  completed_in_period: number;
  overall_completion_rate_pct: number | null;
}

export interface FocusData {
  days: number;
  total_sessions: number;
  avg_duration_sec: number | null;
  completion_pct: number | null;
  total_minutes: number;
}

export interface GamificationData {
  xp: { avg: number | null; max: number | null; median: number | null };
  streaks: { avg: number | null; max: number | null };
  coins: { avg: number | null; total: number | null };
}

export interface RetentionRow {
  signup_date: string;
  cohort_size: number;
  day_1: number;
  day_7: number;
  day_30: number;
}

export interface PostHogResult {
  results: unknown;
  columns?: string[];
  types?: string[];
}

// PostHog query helpers
export type PostHogRow = Record<string, unknown>;

export interface PostHogQueryResult {
  rows: PostHogRow[];
  columns: string[];
  error?: string;
  notConfigured?: boolean;
}

export function parsePostHogResult(raw: unknown): PostHogQueryResult {
  if (raw == null || typeof raw !== "object") {
    return { rows: [], columns: [], error: "Empty response" };
  }
  const obj = raw as Record<string, unknown>;

  if (Array.isArray(obj.results)) {
    const results = obj.results as unknown[];
    if (results.length === 0) return { rows: [], columns: (obj.columns as string[]) ?? [] };

    const firstResult = results[0];
    const cols: string[] = Array.isArray(obj.columns)
      ? (obj.columns as string[])
      : firstResult != null && typeof firstResult === "object"
        ? Object.keys(firstResult as object)
        : [];

    const rows: PostHogRow[] = results.map((r) => {
      if (Array.isArray(r)) {
        const arr = r as unknown[];
        const row: PostHogRow = {};
        cols.forEach((col, i) => {
          row[col] = arr[i];
        });
        return row;
      }
      return r as PostHogRow;
    });

    return { rows, columns: cols };
  }

  return { rows: [], columns: [], error: "Unexpected response shape" };
}

export async function runPostHogQuery(
  token: string,
  query: string
): Promise<PostHogQueryResult> {
  try {
    const raw = await api.postHogQuery(token, query);
    return parsePostHogResult(raw);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.startsWith("501")) {
      return { rows: [], columns: [], notConfigured: true };
    }
    return { rows: [], columns: [], error: msg };
  }
}

export const POSTHOG_QUERIES = {
  screenViews: `SELECT properties.$screen_name AS screen, COUNT() AS views FROM events WHERE event = '$screen' AND timestamp > now() - interval 7 day GROUP BY screen ORDER BY views DESC LIMIT 20`,
  appOpens: `SELECT toDate(timestamp) AS day, COUNT() AS opens FROM events WHERE event = 'app_opened' AND timestamp > now() - interval 30 day GROUP BY day ORDER BY day`,
  eventDist: `SELECT event, COUNT() AS count FROM events WHERE timestamp > now() - interval 7 day GROUP BY event ORDER BY count DESC LIMIT 20`,
};
