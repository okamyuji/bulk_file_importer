const API_BASE = "/api/v1";

let accessToken: string | null = localStorage.getItem("jwt");

export function setToken(token: string | null) {
  accessToken = token;
  if (token) localStorage.setItem("jwt", token);
  else localStorage.removeItem("jwt");
}

export function getToken() {
  return accessToken;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
  if (
    init.body &&
    !(init.body instanceof FormData) &&
    !headers.has("Content-Type")
  ) {
    headers.set("Content-Type", "application/json");
  }

  const res = await fetch(`${API_BASE}${path}`, { ...init, headers });

  if (res.status === 401) {
    setToken(null);
    window.dispatchEvent(new CustomEvent("auth:unauthorized"));
  }

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${body}`);
  }

  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export interface User {
  id: number;
  email: string;
  name: string;
}

export interface CsvImport {
  id: number;
  file_name: string;
  input_kind: "csv" | "binary";
  target_kind: "sales_record" | "ledger_entry" | "binary_asset";
  content_type: string | null;
  byte_size: number;
  status: string;
  total_rows: number;
  processed_rows: number;
  failed_rows: number;
  total_bytes: number;
  processed_bytes: number;
  failed_bytes: number;
  total_chunks: number;
  idempotency_key: string;
  source_checksum: string | null;
  reassembled_display_name: string | null;
  reassembled_checksum: string | null;
  error_message: string | null;
  progress: number;
  created_at: string;
  updated_at: string;
}

export interface CsvImportChunk {
  id: number;
  csv_import_id: number;
  chunk_index: number;
  start_row: number;
  end_row: number;
  start_byte: number | null;
  end_byte: number | null;
  byte_size: number;
  checksum: string | null;
  status: string;
  processed_rows: number;
  failed_rows: number;
  retry_count: number;
  error_details: Array<{
    row?: number | string;
    errors?: string[];
    fatal?: string;
  }> | null;
}

export const api = {
  signIn(email: string, password: string) {
    return fetch(`${API_BASE}/sessions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: { email, password } }),
    }).then(async (res) => {
      const auth = res.headers.get("Authorization");
      if (!res.ok) throw new Error(await res.text());
      const body = (await res.json()) as { user: User; token: string };
      const token = body.token || auth?.replace(/^Bearer\s+/i, "") || null;
      if (token) setToken(token);
      return body.user;
    });
  },

  signUp(email: string, password: string, name: string) {
    return fetch(`${API_BASE}/registrations`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        user: { email, password, password_confirmation: password, name },
      }),
    }).then(async (res) => {
      const auth = res.headers.get("Authorization");
      if (!res.ok) throw new Error(await res.text());
      const body = (await res.json()) as { user: User; token: string };
      const token = body.token || auth?.replace(/^Bearer\s+/i, "") || null;
      if (token) setToken(token);
      return body.user;
    });
  },

  signOut() {
    return request<void>("/sessions", { method: "DELETE" }).finally(() =>
      setToken(null),
    );
  },

  me() {
    return request<User>("/me");
  },

  listImports() {
    return request<{ data: CsvImport[] }>("/csv_imports");
  },

  getImport(id: number) {
    return request<{ data: CsvImport; chunks: CsvImportChunk[] }>(
      `/csv_imports/${id}`,
    );
  },

  createImport(
    file: File,
    target_kind: "sales_record" | "ledger_entry" | "binary_asset",
    input_kind: "csv" | "binary",
    onProgress?: (pct: number) => void,
  ) {
    return new Promise<{ data: CsvImport }>((resolve, reject) => {
      const form = new FormData();
      form.append("file", file);
      form.append("target_kind", target_kind);
      form.append("input_kind", input_kind);

      const xhr = new XMLHttpRequest();
      xhr.open("POST", `${API_BASE}/csv_imports`);
      if (accessToken)
        xhr.setRequestHeader("Authorization", `Bearer ${accessToken}`);
      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable && onProgress)
          onProgress((e.loaded / e.total) * 100);
      };
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300)
          resolve(JSON.parse(xhr.responseText));
        else reject(new Error(`${xhr.status}: ${xhr.responseText}`));
      };
      xhr.onerror = () => reject(new Error("network error"));
      xhr.send(form);
    });
  },

  retryImport(id: number) {
    return request<{ retried: number }>(`/csv_imports/${id}/retry`, {
      method: "POST",
    });
  },
};
