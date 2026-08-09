import * as React from "react";
import { cn } from "@/lib/utils";

export type ButtonVariant = "primary" | "secondary" | "tertiary" | "destructive";

const variantClasses: Record<ButtonVariant, string> = {
  // The brand's primary CTA color is the orange accent, not black — see
  // docs/design-system.md. "Launch App" and other primary actions
  // should read as BitV orange, not blend into a black/white button.
  primary:
    "bg-accent text-accent-foreground hover:bg-accent/90 disabled:opacity-40",
  secondary:
    "border border-border text-foreground hover:bg-muted disabled:opacity-40 disabled:hover:bg-transparent",
  tertiary:
    "text-foreground hover:bg-muted disabled:opacity-40 disabled:hover:bg-transparent",
  destructive:
    "bg-destructive text-destructive-foreground hover:opacity-90 disabled:opacity-40",
};

/** Same visual system as `Button`, exposed as a plain class string for
 * non-`<button>` elements that need to *look* like a button but must
 * stay a different tag for correct semantics — e.g. `<Link>` for
 * in-app navigation (never render a real navigation as a `<button>`
 * with an onClick router push). */
export function buttonVariants(variant: ButtonVariant = "primary", className?: string) {
  return cn(
    "inline-flex h-10 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium transition-colors",
    variantClasses[variant],
    className,
  );
}

/** Shared button system — one consistent height/radius/focus ring
 * across landing and dashboard, with four variants matching the
 * primary/secondary/tertiary/destructive hierarchy. `isLoading` shows
 * a spinner and disables the button without changing its size (so
 * layout doesn't jump), per the "never show success before it's real"
 * pattern already used for the Treasury claim flow. */
export const Button = React.forwardRef<
  HTMLButtonElement,
  React.ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: ButtonVariant;
    isLoading?: boolean;
  }
>(function Button({ variant = "primary", isLoading = false, disabled, className, children, ...props }, ref) {
  return (
    <button
      ref={ref}
      disabled={disabled || isLoading}
      className={cn(
        "inline-flex h-10 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium transition-colors disabled:cursor-not-allowed",
        variantClasses[variant],
        className,
      )}
      {...props}
    >
      {isLoading ? (
        <span
          aria-hidden="true"
          className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current/40 border-t-current"
        />
      ) : null}
      {children}
    </button>
  );
});
