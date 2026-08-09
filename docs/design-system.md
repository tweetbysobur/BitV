# BitV Design System (Build 17)

Source-of-truth summary of BitV's visual identity, consolidating decisions
already encoded in `app/globals.css`, `tailwind.config.ts`, and the shared
`components/ui`/`components/brand` components — not a new system, an audit
and, where a real inconsistency was found, a fix.

## Logo

`components/brand/BitVMark.tsx` — the single source for BitV's mark
(`BitVMark`, icon only) and lockup (`BitVLockup`, icon + wordmark). Traced
directly from the logo file the project owner provided: a black
rounded-square containing a bold white "V" with an orange angled flag cut
into the top of the right leg. `app/icon.svg` mirrors the same path data
for the browser favicon.

Used in: landing nav (`LandingNav.tsx`), dashboard sidebar (`Sidebar.tsx`),
dashboard mobile topbar (`Topbar.tsx`), footer (`LandingFooter.tsx`),
favicon. No second symbol or replacement mark exists anywhere in the repo.

**Fixed this milestone**: the dashboard sidebar/topbar logo linked to
`/dashboard/overview` instead of `/` — clicking it from inside the app
never returned to the marketing site. Both now link to `/`.

## Color tokens

Defined once in `app/globals.css` as HSL CSS custom properties, consumed
via `tailwind.config.ts`'s `colors` map (`background`, `foreground`,
`border`, `card`, `muted`, `accent`, `primary`, `destructive`, `success`,
`warning`). Never hardcode a hex value in a component — reference the
Tailwind class (`bg-accent`, `text-muted-foreground`, etc.) so a token
change propagates everywhere.

| Token | Light value | Role |
|---|---|---|
| `--background` / `--foreground` | white / near-black (`0 0% 5%`) | Page background / primary text |
| `--primary` / `--primary-foreground` | near-black / white | Black surfaces (e.g. active nav state background) |
| `--accent` / `--accent-foreground` | `24 95% 53%` (`#f97015`) / near-black | **BitV orange** — the brand's primary accent |
| `--muted` / `--muted-foreground` | light gray / mid gray | Secondary surfaces and text |
| `--border` | light gray | All borders (`* { @apply border-border }` in `globals.css`) |
| `--destructive`, `--success`, `--warning` | red / green / amber | Semantic status only (compliance failures, health factor, etc.) — never decorative |

**Fixed this milestone — the real "too much black" bug**: `components/ui/button.tsx`'s
`primary` variant was using `bg-primary` (black) instead of `bg-accent`
(orange), even though the brand direction has always said primary CTAs
("Launch App" etc.) should read as BitV orange. Since that button repeats
6+ times across the product, this was the single biggest reason the site
read as black-dominant rather than black-with-an-orange-accent. Now fixed
— `buttonVariants("primary")` and `<Button variant="primary">` both render
in `--accent`. `secondary`/`tertiary` stay restrained black/white/border,
matching "orange only where emphasis is useful."

**Fixed this milestone — wallet connect widget**: RainbowKit's
`ConnectButton` (`components/dashboard/WalletStatus.tsx`) was never themed
and rendered in RainbowKit's own default blue — a jarring off-brand color
on one of the most-seen interactive elements in the whole product.
`components/providers/web3-provider.tsx` now passes RainbowKit's `theme`
prop, mapped onto the same `--accent` orange (`#f97015`) and near-black
foreground, so the connect button reads as part of BitV rather than a
generic crypto widget bolted on.

**No purple, blue, neon, or gradient color was introduced or found**
anywhere in the codebase (re-verified this milestone via a fresh
purple/indigo/violet/blue-\* grep across `app/` and `components/`).

## Dark mode — tokens exist, not currently reachable

`app/globals.css` defines a full `.dark { ... }` token set and
`tailwind.config.ts` sets `darkMode: ["class"]`, but **nothing in the app
ever adds the `.dark` class** — there's no theme toggle, no `next-themes`,
no `prefers-color-scheme` media-query wiring. This is a real, honest gap:
the dark tokens are dead code in practice today, not a working dark mode.
Documenting this rather than claiming dark mode is "supported" — building
an actual toggle is a real feature, not something to imply exists.

## Typography

`lib/fonts.ts` — Poppins (`--font-poppins`, `font-heading`/`font-sans` in
Tailwind) and Montserrat (`--font-montserrat`, `font-body`). Per brand
direction: Poppins for headings/nav/labels/buttons, Montserrat for body
copy — already the case throughout (`h1`-`h6` get `font-heading` globally
via `app/globals.css`; `body` gets `font-body`).

`app/globals.css`'s `@layer base` also sets `tracking-tight` and a `1.15`
line-height on every heading globally (from Build 17's visual-polish
pass), and a `.font-numeric` utility (`font-variant-numeric: tabular-nums`
+ slight negative tracking) for financial values like BitScore, health
factor, and balances — used in the risk cards.

## Buttons

`components/ui/button.tsx` — the one button system, four variants
(`primary`/`secondary`/`tertiary`/`destructive`), consistent `h-10`
height and `rounded-md` radius, a loading state that shows a spinner
without changing the button's size (so the layout never jumps), and
`disabled:opacity-40` for the disabled state. `buttonVariants()` exposes
the identical class string for `<Link>` elements that must stay `<a>`
tags for correct navigation semantics (never render in-app navigation as
a `<button onClick={...}>`). Focus states come from the global
`:focus-visible` ring (see Accessibility below), not a per-component
override.

## Cards

`components/ui/card.tsx` — `Card`/`CardHeader`/`CardTitle`/
`CardDescription`/`CardContent`. Subtle `border-border` border,
`bg-card`, `rounded-lg`, no shadow, restrained padding (`p-4 sm:p-5`).
Deliberately no card variant system — hierarchy inside a card comes from
typography (a card's primary metric is the largest/heaviest text on the
card, e.g. `HealthFactorCard`'s `text-3xl font-semibold`), not from extra
card-level styling.

## Motion

Framer Motion, used for: section entrance reveals (`components/landing/Reveal.tsx`,
`whileInView` + `once: true`), hover/tap feedback via Tailwind transition
classes (not Framer, for simple color/opacity changes), and nothing else
— no parallax, no floating elements, no constant-motion backgrounds.
`app/page.tsx`, `app/product/page.tsx`, and `app/how-it-works/page.tsx`
all wrap in `<MotionConfig reducedMotion="user">`, which defers to the
visitor's OS-level reduced-motion preference automatically. `app/globals.css`
also has a `@media (prefers-reduced-motion: reduce)` block collapsing all
CSS transitions/animations to near-zero duration as a second layer of
defense for the plain-CSS hover transitions Framer doesn't control.

## Navigation

Desktop: Logo → Product → How It Works → Risk → Docs → Launch App
(`components/landing/LandingNav.tsx`). Mobile: logo + hamburger, opening a
simple stacked link list with the same items — not overloaded, since the
link count is already short post-Build-17's landing-page split.

Dashboard: persistent sidebar at `lg`+ (`components/dashboard/Sidebar.tsx`,
logo + 8 route links, each with a lucide icon and an orange left-accent
bar on the active route), collapsible drawer below `lg`
(`components/dashboard/Topbar.tsx`).

## Icons

`lucide-react` exclusively — no other icon library is imported anywhere
in the repo (verified this milestone). Icons are used only for
navigation, status, or actions, never as decoration.

## Responsive behavior

No layout regression introduced this milestone — verified via `npm run
build`'s route output and a live dev-server smoke test of `/`,
`/product`, `/how-it-works`, and representative dashboard routes.
Breakpoint-specific behavior (mobile nav drawer, dashboard sidebar
collapse at `lg`, footer column stacking at `sm`) was already established
in earlier milestones (Build 12/13) and re-confirmed, not rebuilt, here.

## What this milestone did NOT do

Per Prompt 17's explicit scope: did not build `/product`, `/how-it-works`,
`/risk`, or `/rwa` as dedicated pages (already built in the prior
milestone for `/product`/`/how-it-works`; `/risk` and `/rwa` remain
dashboard routes only, as they were). Did not add a dark-mode toggle —
flagged above as a real, currently-unaddressed gap rather than silently
left ambiguous. Did not restructure the footer further (columns/links
were already finalized in the prior milestone).
