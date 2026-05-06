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
          : "JPEG/PNG/WebP/MP4/MOVファイルのみアップロードできます。",
      );
    },
    accept:
      inputKind === "csv"
        ? { "text/csv": [".csv"], "application/vnd.ms-excel": [".csv"] }
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
        <h2 className="text-xl font-semibold">New import</h2>
        <p className="text-sm text-slate-400">
          Upload a CSV or supported media file. Data is streamed, chunked, and
          processed in the background.
        </p>
      </header>

      <div className="flex gap-2 text-sm">
        {(["csv", "binary"] as const).map((k) => (
          <button
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
            {k}
          </button>
        ))}
      </div>

      {inputKind === "csv" && (
        <div className="flex gap-2 text-sm">
          {(["sales_record", "ledger_entry"] as const).map((k) => (
            <button
              key={k}
              onClick={() => setTargetKind(k)}
              className={clsx("rounded-full border px-3 py-1.5 transition", {
                "bg-sky-500 border-sky-500 text-slate-950": targetKind === k,
                "bg-transparent border-slate-700 text-slate-300 hover:border-slate-600":
                  targetKind !== k,
              })}
            >
              {k}
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
            Drag & drop a {inputKind === "csv" ? "CSV" : "media file"}, or click
            to pick one
          </p>
        )}
      </div>

      {uploadPct > 0 && uploadPct < 100 && (
        <p className="text-sm text-slate-400">
          Uploading: {uploadPct.toFixed(0)}%
        </p>
      )}
      {error && <p className="text-sm text-rose-400">{error}</p>}

      <button
        onClick={submit}
        disabled={!file || submitting}
        className="rounded-lg bg-sky-500 hover:bg-sky-400 disabled:opacity-50 text-slate-950 px-4 py-2 font-medium"
      >
        {submitting ? "Uploading…" : "Start import"}
      </button>
    </section>
  );
}
