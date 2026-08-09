import { cn } from "@/lib/utils";

/**
 * BitV's mark: a black rounded-square containing a bold white "V" with
 * an orange angled flag cut into the top of its right leg — traced
 * from the actual uploaded BitV logo (see app/icon.svg, which mirrors
 * this exact mark for the favicon).
 */
export function BitVMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 100 100"
      className={cn("h-8 w-8 shrink-0", className)}
      role="img"
      aria-label="BitV"
    >
      <rect width="100" height="100" rx="26" fill="hsl(0 0% 5%)" />
      <path d="M24 20 L50 80 L76 20 L67 20 L50 62 L33 20 Z" fill="white" />
      <path d="M76 20 L70 34 L61 34 L67 20 Z" fill="hsl(24 95% 53%)" />
    </svg>
  );
}

/** Mark + wordmark, for surfaces with room for the full lockup
 * (landing nav, footer). Dashboard's collapsed mobile topbar uses the
 * mark alone via BitVMark directly. */
export function BitVLockup({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2", className)}>
      <BitVMark />
      <span className="font-heading text-lg font-semibold tracking-tight">BitV</span>
    </span>
  );
}
