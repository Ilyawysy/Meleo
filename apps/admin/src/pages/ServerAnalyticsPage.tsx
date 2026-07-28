import {
  TasksData,
  FocusData,
  GamificationData,
  RetentionRow,
} from "../api/client";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "../components/ui/card";
import { Button } from "../components/ui/button";

function fmt(value: number | null | undefined, fallback = "—"): string {
  if (value == null) return fallback;
  return value.toLocaleString();
}

function fmtPct(value: number | null | undefined): string {
  if (value == null) return "—";
  return `${value.toFixed(1)}%`;
}

function fmtDuration(seconds: number | null | undefined): string {
  if (seconds == null) return "—";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function fmtHours(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  return `${h}h ${m}m`;
}

interface MetricCardProps {
  label: string;
  value: string;
  loading: boolean;
  accent?: string;
}

function MetricCard({ label, value, loading, accent }: MetricCardProps) {
  return (
    <Card className={accent}>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{loading ? "..." : value}</div>
      </CardContent>
    </Card>
  );
}

function retentionColor(pct: number): string {
  if (pct >= 50) return "text-[hsl(var(--chart-2))] font-semibold";
  if (pct >= 20) return "text-[hsl(var(--chart-3))] font-medium";
  return "text-[hsl(var(--muted-foreground))]";
}

const PERIOD_OPTIONS = [7, 30, 90] as const;

interface Props {
  tasks: TasksData | null;
  focus: FocusData | null;
  gamification: GamificationData | null;
  retention: RetentionRow[];
  loading: boolean;
  period: number;
  onPeriodChange: (days: number) => void;
}

export default function ServerAnalyticsPage({
  tasks,
  focus,
  gamification,
  retention,
  loading,
  period,
  onPeriodChange,
}: Props) {
  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold">Server Analytics</h1>

      {/* Tasks */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold">Tasks</h2>
          <div className="flex gap-2">
            {PERIOD_OPTIONS.map((d) => (
              <Button
                key={d}
                size="sm"
                variant={period === d ? "default" : "outline"}
                onClick={() => onPeriodChange(d)}
              >
                {d}d
              </Button>
            ))}
          </div>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <MetricCard
            label={`Created (${period}d)`}
            value={fmt(tasks?.created_in_period)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-1))]"
          />
          <MetricCard
            label={`Completed (${period}d)`}
            value={fmt(tasks?.completed_in_period)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-2))]"
          />
          <MetricCard
            label="Completion Rate"
            value={fmtPct(tasks?.overall_completion_rate_pct)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-3))]"
          />
        </div>
      </section>

      {/* Focus */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Focus Sessions</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <MetricCard
            label={`Total Sessions (${period}d)`}
            value={fmt(focus?.total_sessions)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-4))]"
          />
          <MetricCard
            label="Avg Duration"
            value={fmtDuration(focus?.avg_duration_sec)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-1))]"
          />
          <MetricCard
            label="Completion %"
            value={fmtPct(focus?.completion_pct)}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-2))]"
          />
          <MetricCard
            label={`Total Time (${period}d)`}
            value={focus ? fmtHours(focus.total_minutes) : "—"}
            loading={loading}
            accent="border-l-4 border-l-[hsl(var(--chart-3))]"
          />
        </div>
      </section>

      {/* Gamification */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Gamification</h2>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <Card className="border-l-4 border-l-[hsl(var(--chart-4))]">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
                XP
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
              {loading ? (
                <div className="text-2xl font-bold">...</div>
              ) : (
                <>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Avg: </span>
                    <span className="font-semibold">{fmt(gamification?.xp.avg)}</span>
                  </div>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Max: </span>
                    <span className="font-semibold">{fmt(gamification?.xp.max)}</span>
                  </div>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Median: </span>
                    <span className="font-semibold">{fmt(gamification?.xp.median)}</span>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <Card className="border-l-4 border-l-[hsl(var(--chart-3))]">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
                Streaks
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
              {loading ? (
                <div className="text-2xl font-bold">...</div>
              ) : (
                <>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Avg: </span>
                    <span className="font-semibold">{fmt(gamification?.streaks.avg)}</span>
                  </div>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Max: </span>
                    <span className="font-semibold">{fmt(gamification?.streaks.max)}</span>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <Card className="border-l-4 border-l-[hsl(var(--chart-1))]">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
                Coins
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
              {loading ? (
                <div className="text-2xl font-bold">...</div>
              ) : (
                <>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Avg: </span>
                    <span className="font-semibold">{fmt(gamification?.coins.avg)}</span>
                  </div>
                  <div>
                    <span className="text-[hsl(var(--muted-foreground))]">Total: </span>
                    <span className="font-semibold">{fmt(gamification?.coins.total)}</span>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Retention */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold">Cohort Retention</h2>
        <Card>
          <CardContent className="pt-4 overflow-x-auto">
            {loading ? (
              <div className="text-[hsl(var(--muted-foreground))] py-4">Loading...</div>
            ) : retention.length === 0 ? (
              <div className="text-[hsl(var(--muted-foreground))] py-4">
                No retention data available.
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-[hsl(var(--muted-foreground))]">
                    <th className="text-left py-2 pr-4 font-medium">Signup Date</th>
                    <th className="text-right py-2 pr-4 font-medium">Cohort Size</th>
                    <th className="text-right py-2 pr-4 font-medium">Day 1</th>
                    <th className="text-right py-2 pr-4 font-medium">Day 7</th>
                    <th className="text-right py-2 font-medium">Day 30</th>
                  </tr>
                </thead>
                <tbody>
                  {retention.map((row, i) => {
                    const d1 = row.cohort_size > 0 ? (row.day_1 / row.cohort_size) * 100 : null;
                    const d7 = row.cohort_size > 0 ? (row.day_7 / row.cohort_size) * 100 : null;
                    const d30 = row.cohort_size > 0 ? (row.day_30 / row.cohort_size) * 100 : null;
                    return (
                      <tr
                        key={i}
                        className={`border-b last:border-0 ${i % 2 === 1 ? "bg-[hsl(var(--muted)/.5)]" : ""}`}
                      >
                        <td className="py-2 pr-4">{row.signup_date}</td>
                        <td className="text-right py-2 pr-4">
                          {row.cohort_size.toLocaleString()}
                        </td>
                        <td className={`text-right py-2 pr-4 ${d1 != null ? retentionColor(d1) : ""}`}>
                          {d1 != null ? `${d1.toFixed(1)}%` : "—"}
                        </td>
                        <td className={`text-right py-2 pr-4 ${d7 != null ? retentionColor(d7) : ""}`}>
                          {d7 != null ? `${d7.toFixed(1)}%` : "—"}
                        </td>
                        <td className={`text-right py-2 ${d30 != null ? retentionColor(d30) : ""}`}>
                          {d30 != null ? `${d30.toFixed(1)}%` : "—"}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      </section>
    </div>
  );
}
