export function Skeleton({ className='' }: { className?: string }) {
  return <div className={"animate-pulse rounded-xl bg-neutral-200 dark:bg-neutral-800 " + className} />;
}

