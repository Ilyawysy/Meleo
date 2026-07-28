import { Sun, Moon, Monitor } from "lucide-react";
import { useTheme } from "../hooks/useTheme";

export function ThemeToggle() {
  const { theme, cycleTheme } = useTheme();

  const Icon = theme === "light" ? Sun : theme === "dark" ? Moon : Monitor;
  const label =
    theme === "light" ? "Light" : theme === "dark" ? "Dark" : "System";

  return (
    <button
      onClick={cycleTheme}
      className="inline-flex items-center gap-1.5 rounded-md px-2 py-1.5 text-sm text-[hsl(var(--muted-foreground))] hover:text-[hsl(var(--foreground))] hover:bg-[hsl(var(--accent))] transition-colors"
      title={`Theme: ${label}`}
    >
      <Icon className="h-4 w-4" />
      <span className="hidden sm:inline text-xs">{label}</span>
    </button>
  );
}
