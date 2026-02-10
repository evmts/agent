import { JSX, splitProps } from 'solid-js';
import { cn } from '../../lib/cn';

export type ButtonProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'default' | 'secondary' | 'ghost' | 'destructive';
  size?: 'sm' | 'md' | 'lg';
};

export function Button(props: ButtonProps) {
  const [local, rest] = splitProps(props, ['class', 'variant', 'size']);
  const variant = local.variant ?? 'default';
  const size = local.size ?? 'md';

  const base = 'inline-flex items-center justify-center font-medium rounded-[8px] transition-colors focus:outline-none focus:ring-2 focus:ring-[hsl(var(--ring))] disabled:opacity-50 disabled:pointer-events-none';
  const sizes: Record<string, string> = {
    sm: 'h-6 px-2 text-[11px]',
    md: 'h-8 px-3 text-[13px]',
    lg: 'h-10 px-4 text-[15px]',
  };
  const variants: Record<string, string> = {
    default: 'bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))] hover:brightness-110',
    secondary: 'bg-[hsl(var(--secondary))] text-[hsl(var(--secondary-foreground))] hover:brightness-110',
    ghost: 'bg-transparent text-[color:var(--sm-text-secondary)] hover:bg-[color:var(--sm-pill-bg)]',
    destructive: 'bg-[hsl(var(--destructive))] text-[hsl(var(--destructive-foreground))] hover:brightness-110',
  };

  return (
    <button type="button" class={cn(base, sizes[size], variants[variant], local.class)} {...rest} />
  );
}
