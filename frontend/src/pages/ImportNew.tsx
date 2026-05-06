import { useCallback, useState } from "react";
import { useDropzone } from "react-dropzone";
import { useNavigate } from "react-router-dom";
import { clsx } from "clsx";
import { api } from "../lib/api";

export function ImportNew() {
  const nav = useNavigate();
  const [file, setFile] = useState<File | null>(null);
  const [inputKind, setInputKind] = useState<"csv" | "binary">("csv");
  const [targetKind, setTargetKind] = useState<"sales_record" | "ledger_entry">(
    "sales_record",
  );
  const [uploadPct, setUploadPct] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onDrop = useCallback((accepted: File[]) => {
    if (accepted[0]) {
      setError(null);
      setFile(accepted[0]);
    }
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    onDropRejected: () => {
      setFile(null);
      setError(
        inputKind === "csv"
          ? "CSVファイルのみアップロードできます。"
          : "JPEG / PNG / WebP / MP4 / MOV ファイルのみアップロードできます。",
      );
    },
    accept:
      inputKind === "csv"
        ? {
            "text/csv": [".csv"],
            "application/csv": [".csv"],
            "application/vnd.ms-excel": [".csv"],
          }
        : {
            "image/jpeg": [".jpg", ".jpeg"],
            "image/png": [".png"],
            "image/webp": [".webp"],
            "video/mp4": [".mp4"],
            "video/quicktime": [".mov"],
          },
    maxFiles: 1,
  });

  async function submit() {
    if (!file) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await api.createImport(
        file,
        inputKind === "binary" ? "binary_asset" : targetKind,
        inputKind,
        (p) => setUploadPct(p),
      );
      nav(`/imports/${res.data.id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="space-y-6">
      <header>
        <h2 className="text-xl font-semibold">新規インポート</h2>
        <p className="text-sm text-slate-400">
          CSVまたは画像・動画ファイルをアップロードしてください。バックグラウンドでストリーム読み込み・チャンク分割・並列処理されます。
        </p>
      </header>

      <div
        className="flex gap-2 text-sm"
        role="radiogroup"
        aria-label="ファイル種別"
      >
        {(
          [
            ["csv", "CSV"],
            ["binary", "画像・動画"],
          ] as const
        ).map(([k, label]) => (
          <button
            type="button"
            role="radio"
            aria-checked={inputKind === k}
            key={k}
            onClick={() => {
              setInputKind(k);
              setFile(null);
            }}
            className={clsx("rounded-full border px-3 py-1.5 transition", {
              "bg-sky-500 border-sky-500 text-slate-950": inputKind === k,
              "bg-transparent border-slate-700 text-slate-300 hover:border-slate-600":
                inputKind !== k,
            })}
          >
            {label}
          </button>
        ))}
      </div>

      {inputKind === "csv" && (
        <div
          className="flex gap-2 text-sm"
          role="radiogroup"
          aria-label="CSV取り込み先"
        >
          {(
            [
              ["sales_record", "売上記録"],
              ["ledger_entry", "仕訳"],
            ] as const
          ).map(([k, label]) => (
            <button
              type="button"
              role="radio"
              aria-checked={targetKind === k}
              key={k}
              onClick={() => setTargetKind(k)}
              className={clsx("rounded-full border px-3 py-1.5 transition", {
                "bg-sky-500 border-sky-500 text-slate-950": targetKind === k,
                "bg-transparent border-slate-700 text-slate-300 hover:border-slate-600":
                  targetKind !== k,
              })}
            >
              {label}
            </button>
          ))}
        </div>
      )}

      <div
        {...getRootProps()}
        className={clsx(
          "cursor-pointer rounded-2xl border-2 border-dashed p-14 text-center transition",
          isDragActive
            ? "border-sky-400 bg-sky-500/5"
            : "border-slate-700 hover:border-slate-600",
        )}
      >
        <input {...getInputProps()} data-testid="file-input" />
        {file ? (
          <div>
            <p className="font-medium">{file.name}</p>
            <p className="text-xs text-slate-400">
              {(file.size / 1024).toFixed(1)} KB
            </p>
          </div>
        ) : (
          <p className="text-slate-400">
            {inputKind === "csv" ? "CSVファイル" : "画像・動画ファイル"}
            をドラッグ&ドロップ、またはクリックして選択してください
          </p>
        )}
      </div>

      {uploadPct > 0 && uploadPct < 100 && (
        <p className="text-sm text-slate-400">
          アップロード中: {uploadPct.toFixed(0)}%
        </p>
      )}
      {error && <p className="text-sm text-rose-400">{error}</p>}

      <button
        onClick={submit}
        disabled={!file || submitting}
        className="rounded-lg bg-sky-500 hover:bg-sky-400 disabled:opacity-50 text-slate-950 px-4 py-2 font-medium"
      >
        {submitting ? "アップロード中…" : "インポート開始"}
      </button>
    </section>
  );
}
