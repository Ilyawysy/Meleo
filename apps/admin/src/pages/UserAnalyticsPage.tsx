import { useState, useCallback } from "react";
import { PostHogQueryResult, runPostHogQuery } from "../api/client";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "../components/ui/card";
import { Button } from "../components/ui/button";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import type { PostHogData } from "../App";

interface QueryTableProps {
  result: PostHogQueryResult | null;
  loading: boolean;
}

function QueryTable({ result, loading }: QueryTableProps) {
  if (loading) {
    return (
      <div className="py-4 text-[hsl(var(--muted-foreground))]">Loading...</div>
    );
  }
  if (!result) return null;
  if (result.notConfigured) {
    return (
      <div className="py-4 text-[hsl(var(--muted-foreground))]">
        PostHog not configured. Set POSTHOG_PROJECT_ID and POSTHOG_PERSONAL_API_KEY
        in your backend environment.
      </div>
    );
  }
  if (result.error) {
    return (
      <div className="py-4 text-[hsl(var(--destructive))] text-sm">
        Error: {result.error}
      </div>
    );
  }
  if (result.rows.length === 0) {
    return (
      <div className="py-4 text-[hsl(var(--muted-foreground))]">No data.</div>
    );
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-[hsl(var(--muted-foreground))]">
            {result.columns.map((col) => (
              <th key={col} className="text-left py-2 pr-4 font-medium">
                {col}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {result.rows.map((row, i) => (
            <tr key={i} className={`border-b last:border-0 ${i % 2 === 1 ? "bg-[hsl(var(--muted)/.5)]" : ""}`}>
              {result.columns.map((col) => (
                <td key={col} className="py-2 pr-4">
                  {String(row[col] ?? "—")}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

interface Props {
  posthog: PostHogData;
  loading: boolean;
  token: string;
}

export default function UserAnalyticsPage({ posthog, loading, token }: Props) {
  const [customQuery, setCustomQuery] = useState("");
  const [customResult, setCustomResult] = useState<PostHogQueryResult | null>(null);
  const [customLoading, setCustomLoading] = useState(false);

  const handleRunCustomQuery = useCallback(async () => {
    if (!token || !customQuery.trim()) return;
    setCustomLoading(true);
    try {
      const result = await runPostHogQuery(token, customQuery.trim());
      setCustomResult(result);
    } finally {
      setCustomLoading(false);
    }
  }, [token, customQuery]);

  const appOpensChartData =
    posthog.appOpens && !posthog.appOpens.notConfigured && !posthog.appOpens.error
      ? posthog.appOpens.rows.map((r) => ({ day: String(r.day ?? ""), opens: Number(r.opens ?? 0) }))
      : [];

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold">User Analytics</h1>

      {/* Screen Views */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Screen Views (last 7 days)</h2>
        <Card>
          <CardContent className="pt-4">
            <QueryTable result={posthog.screenViews} loading={loading} />
          </CardContent>
        </Card>
      </section>

      {/* App Opens Chart */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">App Opens (last 30 days)</h2>
        <Card>
          <CardContent className="pt-4">
            {loading ? (
              <div className="py-4 text-[hsl(var(--muted-foreground))]">Loading...</div>
            ) : posthog.appOpens?.notConfigured ? (
              <div className="py-4 text-[hsl(var(--muted-foreground))]">
                PostHog not configured.
              </div>
            ) : posthog.appOpens?.error ? (
              <div className="py-4 text-[hsl(var(--destructive))] text-sm">
                Error: {posthog.appOpens.error}
              </div>
            ) : appOpensChartData.length === 0 ? (
              <div className="py-4 text-[hsl(var(--muted-foreground))]">No data.</div>
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={appOpensChartData} margin={{ top: 4, right: 8, left: 0, bottom: 40 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                  <XAxis
                    dataKey="day"
                    tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                    angle={-45}
                    textAnchor="end"
                    interval="preserveStartEnd"
                  />
                  <YAxis tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} allowDecimals={false} />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: "hsl(var(--card))",
                      borderColor: "hsl(var(--border))",
                      borderRadius: "var(--radius)",
                      color: "hsl(var(--foreground))",
                    }}
                  />
                  <Bar dataKey="opens" fill="hsl(var(--chart-1))" radius={[3, 3, 0, 0] as [number, number, number, number]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </section>

      {/* Event Distribution */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Event Distribution (last 7 days)</h2>
        <Card>
          <CardContent className="pt-4">
            <QueryTable result={posthog.eventDist} loading={loading} />
          </CardContent>
        </Card>
      </section>

      {/* Custom Query */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Custom HogQL Query</h2>
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
              Enter a HogQL query and click Run
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <textarea
              className="w-full rounded-md border border-[hsl(var(--input))] bg-[hsl(var(--muted)/.3)] p-3 text-sm font-mono resize-y min-h-[100px] text-[hsl(var(--foreground))] placeholder:text-[hsl(var(--muted-foreground))] focus:outline-none focus:ring-2 focus:ring-[hsl(var(--ring))] transition-colors"
              value={customQuery}
              onChange={(e) => setCustomQuery(e.target.value)}
              placeholder="SELECT event, COUNT() AS count FROM events GROUP BY event ORDER BY count DESC LIMIT 10"
            />
            <Button
              onClick={handleRunCustomQuery}
              disabled={customLoading || !customQuery.trim()}
              size="sm"
            >
              {customLoading ? "Running..." : "Run Query"}
            </Button>
            {customResult && (
              <div className="pt-2">
                <QueryTable result={customResult} loading={customLoading} />
              </div>
            )}
          </CardContent>
        </Card>
      </section>
    </div>
  );
}
