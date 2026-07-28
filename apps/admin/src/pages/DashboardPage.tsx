import { OverviewData } from "../api/client";
import { Card, CardHeader, CardTitle, CardContent } from "../components/ui/card";

const STAT_ACCENTS = [
  { border: "border-l-4 border-l-[hsl(var(--chart-1))]" },
  { border: "border-l-4 border-l-[hsl(var(--chart-2))]" },
  { border: "border-l-4 border-l-[hsl(var(--chart-3))]" },
  { border: "border-l-4 border-l-[hsl(var(--chart-4))]" },
  { border: "border-l-4 border-l-[hsl(var(--chart-2))]" },
  { border: "border-l-4 border-l-[hsl(var(--chart-1))]" },
];

interface StatCardProps {
  label: string;
  value: number | null | undefined;
  loading: boolean;
  accentIndex?: number;
}

function StatCard({ label, value, loading, accentIndex = 0 }: StatCardProps) {
  const accent = STAT_ACCENTS[accentIndex % STAT_ACCENTS.length]!;
  return (
    <Card className={accent.border}>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-[hsl(var(--muted-foreground))]">
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="text-3xl font-bold">
          {loading ? "..." : value != null ? value.toLocaleString() : "—"}
        </div>
      </CardContent>
    </Card>
  );
}

interface Props {
  overview: OverviewData | null;
  loading: boolean;
}

export default function DashboardPage({ overview, loading }: Props) {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Dashboard</h1>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Total Users" value={overview?.total_users} loading={loading} accentIndex={0} />
        <StatCard label="Active Today" value={overview?.active_today} loading={loading} accentIndex={1} />
        <StatCard label="Active This Week" value={overview?.active_week} loading={loading} accentIndex={2} />
        <StatCard label="Active This Month" value={overview?.active_month} loading={loading} accentIndex={3} />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <StatCard label="New Users Today" value={overview?.new_today} loading={loading} accentIndex={4} />
        <StatCard label="New Users This Week" value={overview?.new_week} loading={loading} accentIndex={5} />
      </div>
    </div>
  );
}
