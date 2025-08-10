type Props = {
  total: number; limit: number; offset: number;
  onChange: (nextOffset: number)=>void;
};
export function Pagination({ total, limit, offset, onChange }: Props) {
  const page = Math.floor(offset/limit)+1;
  const pages = Math.max(1, Math.ceil(total/limit));
  const prev = Math.max(0, offset - limit);
  const next = Math.min((pages-1)*limit, offset + limit);
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <div>ทั้งหมด {total.toLocaleString()} รายการ • หน้า {page}/{pages}</div>
      <div className="flex gap-2">
        <button className="px-3 py-1 rounded-xl border dark:border-neutral-700" disabled={offset===0} onClick={()=>onChange(prev)}>ก่อนหน้า</button>
        <button className="px-3 py-1 rounded-xl border dark:border-neutral-700" disabled={page===pages} onClick={()=>onChange(next)}>ถัดไป</button>
      </div>
    </div>
  );
}

