// src/lib/api.fixed.ts
// API client (clean) — ชี้ไป api.crimeai.local แบบคงที่

console.info("[API_FILE]", import.meta.url);

export const API_BASE = "http://api.crimeai.local";
console.info("[API_BASE]", API_BASE);

// ---------- Types ----------
export type CaseItem = {
  case_id: string;
  CenterCode: string;
  CaseBehavior: string | null;
  SceneDescription: string | null;
  CaseCategoryName: string | null;
  PoliceStationName: string | null;
  ProvinceName: string | null;
};
export type ListResp = { total: number; items: CaseItem[] };
export type Filters = { centers: { code: string; name: string }[]; categories: string[] };

// ---------- Helpers ----------
function makeUrl(
  path: string,
  params?: Record<string, string | number | boolean | null | undefined>
) {
  const url = new URL(path, API_BASE);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    }
  }
  return url.toString();
}

async function safeFetchJSON<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, { headers: { Accept: "application/json" }, ...init });
  if (!r.ok) {
    let msg = `HTTP ${r.status}`;
    try {
      const ct = r.headers.get("content-type") || "";
      if (ct.includes("application/json")) {
        const j: any = await r.json();
        if (j?.detail) msg += ` • ${typeof j.detail === "string" ? j.detail : JSON.stringify(j.detail)}`;
      } else {
        const t = await r.text();
        if (t) msg += ` • ${t.slice(0, 200)}`;
      }
    } catch {}
    throw new Error(msg);
  }
  return r.json() as Promise<T>;
}

// ---------- Endpoints ----------
export async function fetchCases(params: {
  q?: string;
  center?: string;
  category?: string;
  limit?: number;
  offset?: number;
}): Promise<ListResp> {
  return safeFetchJSON<ListResp>(makeUrl("/cases", params));
}

export async function fetchFilters(): Promise<Filters> {
  return safeFetchJSON<Filters>(makeUrl("/cases/filters"));
}

export async function fetchCaseById(id: string): Promise<CaseItem & Record<string, unknown>> {
  return safeFetchJSON(makeUrl(`/cases/${encodeURIComponent(id)}`));
}

