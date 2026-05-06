import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { useAuth } from "../stores/auth";

export function Login() {
  const nav = useNavigate();
  const setUser = useAuth((s) => s.setUser);
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const user =
        mode === "signin"
          ? await api.signIn(email, password)
          : await api.signUp(email, password, name);
      setUser(user);
      nav("/imports");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen grid place-items-center p-6">
      <form
        onSubmit={onSubmit}
        className="w-full max-w-sm space-y-4 rounded-2xl bg-slate-900/70 backdrop-blur p-8 border border-slate-800"
      >
        <h1 className="text-2xl font-semibold tracking-tight">
          {mode === "signin" ? "サインイン" : "アカウント作成"}
        </h1>
        {mode === "signup" && (
          <label className="block text-sm">
            <span className="text-slate-400">お名前</span>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              className="mt-1 w-full rounded-lg bg-slate-800/60 border border-slate-700 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </label>
        )}
        <label className="block text-sm">
          <span className="text-slate-400">メールアドレス</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className="mt-1 w-full rounded-lg bg-slate-800/60 border border-slate-700 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-400">パスワード</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            className="mt-1 w-full rounded-lg bg-slate-800/60 border border-slate-700 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </label>
        {error && <p className="text-sm text-rose-400">{error}</p>}
        <button
          type="submit"
          data-testid="submit"
          disabled={loading}
          className="w-full rounded-lg bg-sky-500 hover:bg-sky-400 disabled:opacity-50 px-4 py-2 font-medium text-slate-950 transition"
        >
          {loading ? "…" : mode === "signin" ? "サインイン" : "新規登録"}
        </button>
        <p className="text-center text-xs text-slate-400">
          {mode === "signin" ? (
            <>
              アカウントをお持ちでないですか？{" "}
              <button
                type="button"
                data-testid="toggle-signup"
                onClick={() => setMode("signup")}
                className="text-sky-400 hover:underline"
              >
                新規登録
              </button>
            </>
          ) : (
            <>
              アカウントをお持ちですか？{" "}
              <button
                type="button"
                onClick={() => setMode("signin")}
                className="text-sky-400 hover:underline"
              >
                サインイン
              </button>
            </>
          )}
        </p>
      </form>
    </main>
  );
}
