import * as React from 'react';

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className='', ...props }, ref) => (
    <input
      ref={ref}
      className={
        "w-full rounded-2xl border px-3 py-2 text-sm outline-none " +
        "border-neutral-300 dark:border-neutral-700 bg-white dark:bg-neutral-900 " +
        "placeholder:text-neutral-400 " + className
      }
      {...props}
    />
  )
);
Input.displayName = 'Input';

