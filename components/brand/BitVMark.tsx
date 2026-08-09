import { cn } from "@/lib/utils";

/**
 * BitV's mark: a black rounded-square containing a white stylized "V"
 * with a small orange accent — per the brand description (no source
 * logo file was ever uploaded to this repo, so this is built directly
 * from that description as inline SVG, not an image asset). Used
 * consistently across landing nav, dashboard sidebar/topbar, footer,
 * and the favicon (see app/icon.svg, which mirrors this exact mark).
 */
export function BitVMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      className={cn("h-8 w-8 shrink-0", className)}
      role="img"
      aria-label="BitV"
    >
      <rect width="32" height="32" rx="8" fill="hsl(0 0% 5%)" />
      <path d="M8 9L15.2 23L16.6 23L23 9L19.7 9L15.9 17.8L12.4 9L8 9Z" fill="white" />
      <circle cx="24.5" cy="9.5" r="2.5" fill="hsl(24 95% 53%)" />
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
