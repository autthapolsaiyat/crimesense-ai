import * as React from 'react';

export function Select({ className='', ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={
        "w-full rounded-2xl border px-3 py-2 text-sm " +
        "border-neutral-300 dark:border-neutral-700 bg-white dark:bg-neutral-900 " + className
      }
      {...props}
    />
  );
}

