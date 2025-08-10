export function Empty({ title="ไม่พบข้อมูล", hint="ลองปรับคำค้นหรือฟิลเตอร์" }:{title?:string; hint?:string}) {
  return (
    <div className="text-center py-16">
      <div className="mx-auto mb-3 h-12 w-12 rounded-2xl bg-neutral-100 dark:bg-neutral-800" />
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="text-sm text-neutral-500 mt-1">{hint}</p>
    </div>
  );
}

