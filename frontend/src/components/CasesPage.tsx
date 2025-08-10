// frontend/src/components/CasesPage.tsx
import { useEffect, useMemo, useRef, useState } from "react";
import { Input } from "./ui/Input";
import { Select } from "./ui/Select";
import { Button } from "./ui/Button";
import { Skeleton } from "./ui/Skeleton";
import { Empty } from "./ui/Empty";
import { Pagination } from "./ui/Pagination";
// ใช้ไฟล์ API ที่ล็อก BASE แล้ว
import { fetchCases, fetchFilters, type CaseItem } from "../lib/api.fixed";
import { toast } from "sonner";
import { Search } from "lucide-react";

const LIMIT = 20;

// รองรับทั้งแบบ object และ string (API อาจคืน categories เป็น object {code,name,count})
type CenterOpt = { code: string; name: string; count?: number };
type CategoryRaw = { code?: string; name?: string; count?: number } | string;

export default function CasesPage() {
  const [q, setQ] = useState("");
  const [center, setCenter] = useState<string>("");
  const [category, setCategory] = useState<string>("");
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<CaseItem[]>([]);
  const [total, setTotal] = useState(0);

  const [filters, setFilters] = useState<{
    centers: CenterOpt[];
    categories: CategoryRaw[];
  } | null>(null);

  const controller = useRef<AbortController | null>(null);

  // โหลดฟิลเตอร์
  useEffect(() => {
    fetchFilters()
      .then((res: any) => setFilters(res))
      .catch(() => toast.error("โหลดฟิลเตอร์ล้มเหลว"));
  }, []);

  // สร้าง option ที่ “ปลอดภัย” เป็น string เสมอ
  const centerOptions = useMemo<CenterOpt[]>(() => {
    return (filters?.centers ?? []).map((c: any) => ({
      code: String(c?.code ?? c?.name ?? ""),
      name: String(c?.name ?? c?.code ?? ""),
      count: typeof c?.count === "number" ? c.count : undefined,
    }));
  }, [filters]);

  const categoryOptions = useMemo(() => {
    const raw = filters?.categories ?? [];
    return raw
      .map((c: CategoryRaw) =>
        typeof c === "string"
          ? { code: c, name: c, count: undefined }
          : {
              code: String(c?.code ?? c?.name ?? ""),
              name: String(c?.name ?? c?.code ?? ""),
              count: typeof c?.count === "number" ? c.count : undefined,
            }
      )
      .filter((c) => c.name); // กันค่าแปลก ๆ
  }, [filters]);

  // ค้นหา (debounce 400ms)
  const params = useMemo(
    () => ({ q, center, category, limit: LIMIT, offset }),
    [q, center, category, offset]
  );

  useEffect(() => {
    setLoading(true);
    controller.current?.abort();
    controller.current = new AbortController();

    const id = setTimeout(() => {
      fetchCases(params)
        .then((res) => {
          setItems(res.items);
          setTotal(res.total);
        })
        .catch((err: any) => {
          if (err?.name !== "AbortError") toast.error("โหลดรายการคดีล้มเหลว");
        })
        .finally(() => setLoading(false));
    }, 400);

    return () => {
      clearTimeout(id);
      controller.current?.abort();
    };
  }, [params]);

  const resetOffset = () => setOffset(0);
  const onSearch = (v: string) => {
    setQ(v);
    resetOffset();
  };
  const onChangeCenter = (v: string) => {
    setCenter(v);
    resetOffset();
  };
  const onChangeCategory = (v: string) => {
    setCategory(v);
    resetOffset();
  };

  return (
    <div className="grid grid-cols-12 gap-6">
      {/* Filters */}
      <aside className="col-span-12 md:col-span-3 lg:col-span-2">
        <div className="sticky top-4 space-y-3 p-4 rounded-2xl border dark:border-neutral-800">
          <div className="font-semibold">ฟิลเตอร์</div>

          <div className="space-y-2">
            <label className="text-xs text-neutral-500">ค้นหา</label>
            <div className="flex gap-2">
              <Input
                placeholder="คำ/พฤติการณ์/สถานที่..."
                value={q}
                onChange={(e) => onSearch(e.target.value)}
              />
              <Button onClick={() => onSearch(q)} aria-label="ค้นหา">
                <Search size={16} />
              </Button>
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-xs text-neutral-500">ศูนย์</label>
            <Select value={center} onChange={(e) => onChangeCenter(e.target.value)}>
              <option key="__all" value="">
                ทั้งหมด
              </option>
              {centerOptions.map((c, i) => (
                <option key={`${c.code}-${i}`} value={c.code}>
                  {c.name}
                  {typeof c.count === "number" ? ` (${c.count})` : ""}
                </option>
              ))}
            </Select>
          </div>

          <div className="space-y-2">
            <label className="text-xs text-neutral-500">หมวดคดี</label>
            <Select value={category} onChange={(e) => onChangeCategory(e.target.value)}>
              <option key="__all" value="">
                ทั้งหมด
              </option>
              {categoryOptions.map((c, i) => (
                <option key={`${c.code}-${i}`} value={c.code}>
                  {c.name}
                  {typeof c.count === "number" ? ` (${c.count})` : ""}
                </option>
              ))}
            </Select>
          </div>

          <Button
            onClick={() => {
              setQ("");
              setCenter("");
              setCategory("");
              resetOffset();
            }}
          >
            ล้างฟิลเตอร์
          </Button>
        </div>
      </aside>

      {/* List */}
      <section className="col-span-12 md:col-span-9 lg:col-span-10">
        <header className="flex items-center justify-between mb-3">
          <h2 className="text-xl font-semibold">รายการคดี</h2>
          <div className="text-sm text-neutral-500">
            {!loading && `พบ ${total.toLocaleString()} รายการ`}
          </div>
        </header>

        <div className="rounded-2xl border dark:border-neutral-800 overflow-hidden">
          {/* Header row */}
          <div className="grid grid-cols-[140px_1fr_220px_180px] gap-4 px-4 py-3 text-xs font-medium bg-neutral-50 dark:bg-neutral-900 border-b dark:border-neutral-800">
            <div>รหัสคดี</div>
            <div>พฤติการณ์ / สถานที่</div>
            <div>หมวดคดี</div>
            <div>ศูนย์/สถานี</div>
          </div>

          {/* Body */}
          {loading ? (
            <div className="p-4 space-y-3">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="grid grid-cols-[140px_1fr_220px_180px] gap-4 items-center">
                  <Skeleton className="h-4 w-28" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-40" />
                  <Skeleton className="h-4 w-32" />
                </div>
              ))}
            </div>
          ) : items.length === 0 ? (
            <Empty />
          ) : (
            <div className="divide-y dark:divide-neutral-800">
              {items.map((row) => (
                <a
                  key={row.case_id}
                  href={`/cases/${encodeURIComponent(row.case_id)}`}
                  className="grid grid-cols-[140px_1fr_220px_180px] gap-4 px-4 py-3 hover:bg-neutral-50 dark:hover:bg-neutral-900"
                >
                  <div className="font-mono text-xs">{row.case_id}</div>
                  <div className="text-sm">
                    <div className="line-clamp-1">{row.CaseBehavior || "-"}</div>
                    <div className="text-xs text-neutral-500 line-clamp-1">
                      {row.SceneDescription || "-"}
                    </div>
                  </div>
                  <div className="text-sm">{row.CaseCategoryName || "-"}</div>
                  <div className="text-xs text-neutral-600 dark:text-neutral-400">
                    <div className="line-clamp-1">{row.CenterCode}</div>
                    <div className="line-clamp-1">{row.PoliceStationName || "-"}</div>
                  </div>
                </a>
              ))}
            </div>
          )}
        </div>

        {/* Pagination */}
        {!loading && items.length > 0 && (
          <div className="mt-4">
            <Pagination total={total} limit={LIMIT} offset={offset} onChange={setOffset} />
          </div>
        )}
      </section>
    </div>
  );
}

