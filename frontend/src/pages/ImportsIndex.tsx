import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { api } from "../lib/api";
import { ProgressBar } from "../components/ProgressBar";
import { StatusBadge } from "../components/StatusBadge";

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

export function ImportsIndex() {
  const { data, isLoading, refetch } = useQuery({
    queryKey: ["imports"],
    queryFn: () => api.listImports(),
    refetchInterval: 3000,
  });

  return (
    <section className="space-y-4">
      <header className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Your imports</h2>
        <Link
          to="/imports/new"
          className="rounded-lg bg-sky-500 hover:bg-sky-400 text-slate-950 px-3 py-1.5 text-sm font-medium"
        >
          + New upload
        </Link>
      </header>

      {isLoading ? (
        <p className="text-slate-400 text-sm">Loading…</p>
      ) : (data?.data ?? []).length === 0 ? (
        <div className="rounded-2xl border border-dashed border-slate-700 p-10 text-center text-slate-400">
          No imports yet. Start by uploading a file.
        </div>
      ) : (
        <ul className="space-y-3">
          {data!.data.map((imp) => (
            <li
              key={imp.id}
              className="rounded-xl border border-slate-800 bg-slate-900/50 p-4 hover:border-slate-700 transition"
            >
              <Link to={`/imports/${imp.id}`} className="block space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium truncate">{imp.file_name}</p>
                    <p className="text-xs text-slate-400">
                      {imp.target_kind} ·{" "}
                      {imp.input_kind === "binary"
                        ? formatBytes(imp.total_bytes || imp.byte_size)
                        : `${imp.total_rows} rows`}{" "}
                      · {imp.total_chunks} chunks
                    </p>
                  </div>
                  <StatusBadge status={imp.status} />
                </div>
                <ProgressBar value={imp.progress} status={imp.status} />
              </Link>
            </li>
          ))}
        </ul>
      )}
      <button
        onClick={() => refetch()}
        className="text-xs text-slate-500 hover:text-slate-300"
      >
        Refresh
      </button>
    </section>
  );
}
