import { useMemo } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "../lib/api";
import { useImportProgress } from "../hooks/useImportProgress";
import { ProgressBar } from "../components/ProgressBar";
import { StatusBadge } from "../components/StatusBadge";

function formatBytes(value: number) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = value;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function formatByteRange(start: number | null, end: number | null) {
  if (start === null || end === null) return "—";

  return `${start}–${end}`;
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
  const metrics: Array<[string, string | number]> = imp
    ? imp.input_kind === "binary"
      ? [
          ["合計", formatBytes(imp.total_bytes || imp.byte_size)],
          ["処理済み", formatBytes(imp.processed_bytes)],
          ["失敗", formatBytes(imp.failed_bytes)],
          ["チャンク数", imp.total_chunks],
        ]
      : [
          ["合計", imp.total_rows],
          ["処理済み", imp.processed_rows],
          ["失敗", imp.failed_rows],
          ["チャンク数", imp.total_chunks],
        ]
    : [];

  const hasFailedChunk = useMemo(
    () => chunks.some((c) => c.status === "failed"),
    [chunks],
  );

  if (!imp) return <p className="text-sm text-slate-400">読み込み中…</p>;

  return (
    <section className="space-y-6">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">{imp.file_name}</h2>
          <p className="text-xs text-slate-400">
            {imp.input_kind} · {imp.target_kind} · 冪等キー{" "}
            {imp.idempotency_key.slice(0, 12)}…
          </p>
        </div>
        <StatusBadge status={imp.status} />
      </header>

      <ProgressBar value={imp.progress} status={imp.status} />

      <dl className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {metrics.map(([k, v]) => (
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
          {retry.isPending ? "再実行中…" : "失敗チャンクを再実行"}
        </button>
      )}

      {imp.reassembled_display_name && (
        <p className="rounded-lg border border-slate-800 bg-slate-900/50 px-3 py-2 text-xs text-slate-300">
          再構成: {imp.reassembled_display_name}
        </p>
      )}

      <section>
        <h3 className="text-sm font-semibold mb-2 text-slate-300">チャンク</h3>
        <div className="overflow-auto rounded-xl border border-slate-800">
          <table className="min-w-full text-xs">
            <thead className="bg-slate-900/80 text-slate-400">
              <tr>
                <th className="px-3 py-2 text-left">#</th>
                <th className="px-3 py-2 text-left">
                  {imp.input_kind === "binary" ? "バイト範囲" : "行範囲"}
                </th>
                <th className="px-3 py-2 text-left">ステータス</th>
                <th className="px-3 py-2 text-right">成功</th>
                <th className="px-3 py-2 text-right">失敗</th>
                <th className="px-3 py-2 text-right">再試行</th>
                <th className="px-3 py-2 text-left">エラー</th>
              </tr>
            </thead>
            <tbody>
              {chunks.map((c) => (
                <tr key={c.id} className="border-t border-slate-800">
                  <td className="px-3 py-2">{c.chunk_index}</td>
                  <td className="px-3 py-2 font-mono">
                    {imp.input_kind === "binary"
                      ? formatByteRange(c.start_byte, c.end_byte)
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
                        {c.start_row != null
                          ? `行 ${e.row ?? "—"}`
                          : "チャンク"}
                        : {(e.errors ?? [e.fatal]).join(", ")}
                      </div>
                    ))}
                    {(c.error_details ?? []).length > 2 && (
                      <div>… 他 +{(c.error_details ?? []).length - 2} 件</div>
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
          最新イベント: {lastEvent.event}
        </p>
      )}
    </section>
  );
}
