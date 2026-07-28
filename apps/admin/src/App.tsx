import { useState, useEffect, useCallback } from "react";
import { Routes, Route, Navigate, Link, useLocation } from "react-router-dom";
import { useAuth } from "./hooks/useAuth";
import {
  api,
  OverviewData,
  TasksData,
  FocusData,
  GamificationData,
  RetentionRow,
  PostHogQueryResult,
  runPostHogQuery,
  POSTHOG_QUERIES,
} from "./api/client";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import ServerAnalyticsPage from "./pages/ServerAnalyticsPage";
import UserAnalyticsPage from "./pages/UserAnalyticsPage";
import { Button } from "./components/ui/button";
import { ThemeToggle } from "./components/ThemeToggle";

// All analytics data in one place
export interface PostHogData {
  screenViews: PostHogQueryResult | null;
  appOpens: PostHogQueryResult | null;
  eventDist: PostHogQueryResult | null;
}

export interface AnalyticsData {
  overview: OverviewData | null;
  tasks: TasksData | null;
  focus: FocusData | null;
  gamification: GamificationData | null;
  retention: RetentionRow[];
  posthog: PostHogData;
}

const emptyPosthog: PostHogData = {
  screenViews: null,
  appOpens: null,
  eventDist: null,
};

const emptyData: AnalyticsData = {
  overview: null,
  tasks: null,
  focus: null,
  gamification: null,
  retention: [],
  posthog: emptyPosthog,
};

function NavLink({ to, children }: { to: string; children: React.ReactNode }) {
  const location = useLocation();
  const isActive = location.pathname === to;
  return (
    <Link
      to={to}
      className={`text-sm ${
        isActive
          ? "text-[hsl(var(--foreground))] font-medium"
          : "text-[hsl(var(--muted-foreground))] hover:text-[hsl(var(--foreground))]"
      }`}
    >
      {children}
    </Link>
  );
}

function Layout({
  children,
  loading,
  onRefresh,
  lastFetched,
}: {
  children: React.ReactNode;
  loading: boolean;
  onRefresh: () => void;
  lastFetched: number | null;
}) {
  const { signOut } = useAuth();
  return (
    <div className="min-h-screen bg-[hsl(var(--background))]">
      <nav className="sticky top-0 z-50 border-b bg-[hsl(var(--card)/.8)] backdrop-blur-md supports-[backdrop-filter]:bg-[hsl(var(--card)/.6)]">
        <div className="mx-auto flex h-14 max-w-7xl items-center justify-between px-4">
          <div className="flex items-center gap-6">
            <span className="text-lg font-bold tracking-tight">Meleo Admin</span>
            <NavLink to="/">Dashboard</NavLink>
            <NavLink to="/server">Server Analytics</NavLink>
            <NavLink to="/users">User Analytics</NavLink>
          </div>
          <div className="flex items-center gap-3">
            {lastFetched && (
              <span className="text-xs text-[hsl(var(--muted-foreground))]">
                Updated {new Date(lastFetched).toLocaleTimeString()}
              </span>
            )}
            <Button onClick={onRefresh} disabled={loading} variant="outline" size="sm">
              {loading ? "Loading..." : "Refresh"}
            </Button>
            <ThemeToggle />
            <button
              onClick={signOut}
              className="text-sm text-[hsl(var(--muted-foreground))] hover:text-[hsl(var(--foreground))] transition-colors"
            >
              Sign out
            </button>
          </div>
        </div>
      </nav>
      <main className="mx-auto max-w-7xl p-6">{children}</main>
    </div>
  );
}

export default function App() {
  const { session, loading: authLoading, isAdmin, signOut } = useAuth();
  const [data, setData] = useState<AnalyticsData>(emptyData);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastFetched, setLastFetched] = useState<number | null>(null);
  const [period, setPeriod] = useState(30);

  const fetchAll = useCallback(
    async (days?: number) => {
      if (!session?.access_token) return;
      const d = days ?? period;
      setLoading(true);
      setError(null);
      try {
        const [overview, tasks, focus, gamification, retention, screenViews, appOpens, eventDist] =
          await Promise.all([
            api.getOverview(session.access_token),
            api.getTasks(session.access_token, d),
            api.getFocus(session.access_token, d),
            api.getGamification(session.access_token),
            api.getRetention(session.access_token),
            runPostHogQuery(session.access_token, POSTHOG_QUERIES.screenViews),
            runPostHogQuery(session.access_token, POSTHOG_QUERIES.appOpens),
            runPostHogQuery(session.access_token, POSTHOG_QUERIES.eventDist),
          ]);
        setData({
          overview, tasks, focus, gamification, retention,
          posthog: { screenViews, appOpens, eventDist },
        });
        setLastFetched(Date.now());
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to fetch data");
        console.error("Failed to fetch analytics", e);
      } finally {
        setLoading(false);
      }
    },
    [session?.access_token, period]
  );

  // Fetch once after auth
  useEffect(() => {
    if (session?.access_token && isAdmin && !lastFetched) {
      fetchAll();
    }
  }, [session?.access_token, isAdmin, lastFetched, fetchAll]);

  const handleRefresh = useCallback(() => {
    fetchAll();
  }, [fetchAll]);

  const handlePeriodChange = useCallback(
    (days: number) => {
      setPeriod(days);
      fetchAll(days);
    },
    [fetchAll]
  );

  if (authLoading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <p className="text-[hsl(var(--muted-foreground))]">Loading...</p>
      </div>
    );
  }

  if (!session) {
    return (
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  if (!isAdmin) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4">
        <p className="text-lg font-semibold text-[hsl(var(--destructive))]">
          Access Denied
        </p>
        <p className="text-[hsl(var(--muted-foreground))]">
          Your account does not have admin privileges.
        </p>
        <button
          onClick={signOut}
          className="text-sm underline text-[hsl(var(--muted-foreground))]"
        >
          Sign out
        </button>
      </div>
    );
  }

  return (
    <Layout loading={loading} onRefresh={handleRefresh} lastFetched={lastFetched}>
      {error && (
        <div className="mb-4 rounded-md border border-[hsl(var(--destructive)/.3)] bg-[hsl(var(--destructive)/.1)] p-3 text-sm text-[hsl(var(--destructive))]">
          {error}
        </div>
      )}
      <Routes>
        <Route
          path="/"
          element={
            <DashboardPage
              overview={data.overview}
              loading={loading}
            />
          }
        />
        <Route
          path="/server"
          element={
            <ServerAnalyticsPage
              tasks={data.tasks}
              focus={data.focus}
              gamification={data.gamification}
              retention={data.retention}
              loading={loading}
              period={period}
              onPeriodChange={handlePeriodChange}
            />
          }
        />
        <Route
          path="/users"
          element={
            <UserAnalyticsPage
              posthog={data.posthog}
              loading={loading}
              token={session.access_token}
            />
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Layout>
  );
}
