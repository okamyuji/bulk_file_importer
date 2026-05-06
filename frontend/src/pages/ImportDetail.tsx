import { useMemo } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "../lib/api";
import { useImportProgress } from "../hooks/useImportProgress";
import { ProgressBar } from "../components/ProgressBar";
import { StatusBadge } from "../components/StatusBadge";

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

export function ImportDetail() {
  const { id } = useParams();
  const importId = Number(id);
  const qc = useQueryClient();

  const { data } = useQuery({
    queryKey: ["import", importId],
    queryFn: () => api.getImport(importId),
    refetchInterval: 2000,
  });

  const retry = useMutation({
    mutationFn: () => api.retryImport(importId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["import", importId] }),
  });

  const events = useImportProgress(importId);
  const lastEvent = events[events.length - 1];

  const imp = data?.data;
  const chunks = useMemo(() => data?.chunks ?? [], [data?.chunks]);

  const hasFailedChunk = useMemo(
    () => chunks.some((c) => c.status === "failed"),
    [chunks],
  );

  if (!imp) return <p className="text-sm text-slate-400">Loading…</p>;

  return (
    <section className="space-y-6">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">{imp.file_name}</h2>
          <p className="text-xs text-slate-400">
            {imp.input_kind} · {imp.target_kind} · idempotency{" "}
            {imp.idempotency_key.slice(0, 12)}…
          </p>
        </div>
        <StatusBadge status={imp.status} />
      </header>

      <ProgressBar value={imp.progress} status={imp.status} />

      <dl className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {(imp.input_kind === "binary"
          ? [
              ["total", formatBytes(imp.total_bytes || imp.byte_size)],
              ["processed", formatBytes(imp.processed_bytes)],
              ["failed", formatBytes(imp.failed_bytes)],
              ["chunks", imp.total_chunks],
            ]
          : [
              ["total", imp.total_rows],
              ["processed", imp.processed_rows],
              ["failed", imp.failed_rows],
              ["chunks", imp.total_chunks],
            ]
        ).map(([k, v]) => (
          <div
            key={k}
            className="rounded-xl border border-slate-800 bg-slate-900/50 p-4"
          >
            <dt className="text-xs uppercase tracking-wide text-slate-500">
              {k}
            </dt>
            <dd className="mt-1 text-2xl font-semibold">{v}</dd>
          </div>
        ))}
      </dl>

      {hasFailedChunk && (
        <button
          onClick={() => retry.mutate()}
          disabled={retry.isPending}
          className="rounded-lg bg-amber-500 hover:bg-amber-400 disabled:opacity-50 text-slate-950 px-4 py-2 text-sm font-medium"
        >
          {retry.isPending ? "Retrying…" : "Retry failed chunks"}
        </button>
      )}

      {imp.reassembled_s3_key && (
        <p className="rounded-lg border border-slate-800 bg-slate-900/50 px-3 py-2 text-xs text-slate-300">
          Reassembled: {imp.reassembled_s3_key}
        </p>
      )}

      <section>
        <h3 className="text-sm font-semibold mb-2 text-slate-300">Chunks</h3>
        <div className="overflow-auto rounded-xl border border-slate-800">
          <table className="min-w-full text-xs">
            <thead className="bg-slate-900/80 text-slate-400">
              <tr>
                <th className="px-3 py-2 text-left">#</th>
                <th className="px-3 py-2 text-left">
                  {imp.input_kind === "binary" ? "Bytes" : "Rows"}
                </th>
                <th className="px-3 py-2 text-left">Status</th>
                <th className="px-3 py-2 text-right">OK</th>
                <th className="px-3 py-2 text-right">Failed</th>
                <th className="px-3 py-2 text-right">Retries</th>
                <th className="px-3 py-2 text-left">Errors</th>
              </tr>
            </thead>
            <tbody>
              {chunks.map((c) => (
                <tr key={c.id} className="border-t border-slate-800">
                  <td className="px-3 py-2">{c.chunk_index}</td>
                  <td className="px-3 py-2 font-mono">
                    {imp.input_kind === "binary"
                      ? `${c.start_byte ?? 0}–${c.end_byte ?? 0}`
                      : `${c.start_row}–${c.end_row}`}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge status={c.status} />
                  </td>
                  <td className="px-3 py-2 text-right">{c.processed_rows}</td>
                  <td className="px-3 py-2 text-right">{c.failed_rows}</td>
                  <td className="px-3 py-2 text-right">{c.retry_count}</td>
                  <td className="px-3 py-2 text-slate-400">
                    {(c.error_details ?? []).slice(0, 2).map((e, i) => (
                      <div key={i}>
                        row {e.row ?? "—"}: {(e.errors ?? [e.fatal]).join(", ")}
                      </div>
                    ))}
                    {(c.error_details ?? []).length > 2 && (
                      <div>… +{(c.error_details ?? []).length - 2} more</div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {lastEvent && (
        <p data-testid="last-cable-event" className="text-xs text-slate-500">
          last realtime: {lastEvent.event}
        </p>
      )}
    </section>
  );
}
