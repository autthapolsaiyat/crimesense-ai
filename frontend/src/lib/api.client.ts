cd frontend/src/lib
cat > api.client.ts <<'TS'
export type CaseItem = {
  case_id: string; CenterCode: string;
  CaseBehavior: string | null; SceneDescription: string | null;
  CaseCategoryName: string | null; PoliceStationName: string | null; ProvinceName: string | null;
};
export type ListResp = { total: number; items: CaseItem[] };
export type Filters = { centers: { code: string; name: string }[]; categories: string[] };

// === API client (LOCKED BASE) — v3-force-rename ===
console.info("[API_CLIENT]", "v3-force-rename loaded");
export const API_BASE = "http://api.crimeai.local";
(console as any).log?.("[API_BASE]", API_BASE);

function makeUrl(path: string, params?: Record<string, string | number | boolean | null | undefined>) {
  const url = new URL(path, API_BASE);
  if (params) for (const [k,v] of Object.entries(params)) if (v!==undefined && v!==null && v!=="") url.searchParams.set(k, String(v));
  return url.toString();
}
async function safeFetchJSON<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, { headers: { Accept: "application/json" }, ...init });
  if (!r.ok) {
    let msg = `HTTP ${r.status}`;
    try { const j:any = await r.json(); if (j?.detail) msg += ` • ${typeof j.detail==='string'? j.detail : JSON.stringify(j.detail)}`; } catch {}
    throw new Error(msg);
  }
  return r.json() as Promise<T>;
}

export async function fetchCases(params: { q?: string; center?: string; category?: string; limit?: number; offset?: number; }): Promise<ListResp> {
  return safeFetchJSON<ListResp>(makeUrl("/cases", params));
}
export async function fetchFilters(): Promise<Filters> {
  return safeFetchJSON<Filters>(makeUrl("/cases/filters"));
}
export async function fetchCaseById(id: string): Promise<CaseItem & Record<string, unknown>> {
  return safeFetchJSON(makeUrl(`/cases/${encodeURIComponent(id)}`));
}
TS

