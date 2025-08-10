import * as React from 'react';

export function Button({ className='', ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      className={
        "inline-flex items-center justify-center rounded-2xl px-4 py-2 text-sm font-medium shadow-sm border border-transparent " +
        "bg-black text-white dark:bg-white dark:text-black hover:opacity-90 active:opacity-80 " +
        "disabled:opacity-50 disabled:pointer-events-none " + className
      }
      {...props}
    />
  );
}

