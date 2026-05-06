import { useEffect } from "react";
import {
  BrowserRouter,
  Navigate,
  Route,
  Routes,
  Link,
  Outlet,
  useNavigate,
} from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useAuth } from "./stores/auth";
import { Login } from "./pages/Login";
import { ImportsIndex } from "./pages/ImportsIndex";
import { ImportNew } from "./pages/ImportNew";
import { ImportDetail } from "./pages/ImportDetail";

const qc = new QueryClient();

function Layout() {
  const user = useAuth((s) => s.user);
  const signOut = useAuth((s) => s.signOut);
  const nav = useNavigate();

  async function logout() {
    await signOut();
    nav("/login");
  }

  return (
    <div className="min-h-screen">
      <header className="border-b border-slate-800 bg-slate-950/50 backdrop-blur px-6 py-3 flex items-center justify-between">
        <Link to="/imports" className="font-semibold tracking-tight">
          bulk_file_importer
        </Link>
        <div className="flex items-center gap-3 text-sm text-slate-400">
          <span data-testid="nav-user">
            {user?.name} ({user?.email})
          </span>
          <button onClick={logout} className="text-slate-300 hover:text-white">
            サインアウト
          </button>
        </div>
      </header>
      <main className="mx-auto max-w-4xl p-6">
        <Outlet />
      </main>
    </div>
  );
}

function Protected() {
  const { user, initialized } = useAuth();
  if (!initialized)
    return <p className="p-6 text-sm text-slate-400">読み込み中…</p>;
  if (!user) return <Navigate to="/login" replace />;
  return <Layout />;
}

export default function App() {
  const init = useAuth((s) => s.init);
  useEffect(() => {
    void init();
  }, [init]);

  return (
    <QueryClientProvider client={qc}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route element={<Protected />}>
            <Route path="/imports" element={<ImportsIndex />} />
            <Route path="/imports/new" element={<ImportNew />} />
            <Route path="/imports/:id" element={<ImportDetail />} />
          </Route>
          <Route path="*" element={<Navigate to="/imports" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
