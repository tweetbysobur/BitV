# BitV — Product Design Specification

**The Trust Layer for DeFi.**
Implementation-ready UI/UX spec. Companion to [`ARCHITECTURE.md`](./ARCHITECTURE.md) — screens, flows, and components here map 1:1 to the sitemap and feature hierarchy defined there. No code; every value below (spacing, radius, type scale, timing) is a decision, not a placeholder, and should be lifted directly into Tailwind/shadcn config when build starts.

---

## Design principles (the filter for every decision below)

1. **Trust is designed, not stated.** No badge, checkmark, or "verified" pill does trust-work by itself. Trust comes from: numbers that are always exact and never jump, states that are never ambiguous (loading vs. stale vs. error look different), and every risk being shown *before* the action that creates it, not after.
2. **Black is the canvas, not a mood.** The UI is quiet by default so that when orange appears — one primary action, one critical number, one active state — it is unambiguous what matters on the screen.
3. **A number is either exact or explicitly approximate.** Never round silently. Never animate a number changing unless the underlying value actually changed.
4. **Institutional and retail share one system, not two skins.** The institutional console uses denser tables and more keyboard affordance; it is the same components at a different density setting, never a different visual language.
5. **Every screen answers "what changed, what's at risk, what can I do."** In that order, top to bottom.

---

## 1. Design System

### 1.1 Color palette

Base neutrals are engineered, not picked — an 11-step scale gives real elevation without ever reaching for a tint of orange to separate surfaces (a common cheap-fintech tell).

**Core brand**
| Token | Hex | Usage |
|---|---|---|
| `bg-canvas` | `#0B0B0D` | App background, primary black |
| `bg-canvas-raised` | `#131316` | Cards, panels — one step up from canvas |
| `bg-canvas-overlay` | `#1B1B1F` | Modals, popovers, dropdowns |
| `bg-canvas-sunken` | `#000000` | Code blocks, table zebra, input wells |
| `accent-500` | `#F97316` | Primary action, active state, critical single number |
| `accent-600` | `#EA6A0C` | Accent hover/pressed |
| `accent-400` | `#FB923C` | Accent on dark, subtle highlights, focus rings |
| `accent-950` | `#2A1206` | Accent-tinted background (badges, chips) — 8% orange on black, not a gradient |

**Neutral scale (gray/slate, cool-neutral to keep black feeling premium, not warm/cheap)**
| Token | Hex | Usage |
|---|---|---|
| `neutral-0` | `#FFFFFF` | Primary text on dark, white surfaces (light mode canvas) |
| `neutral-100` | `#F4F4F5` | Secondary surface (light mode) |
| `neutral-300` | `#A1A1AA` | Secondary text, placeholder |
| `neutral-500` | `#71717A` | Tertiary text, disabled |
| `neutral-700` | `#3F3F46` | Borders on dark, dividers |
| `neutral-800` | `#27272A` | Card borders, input borders (default state) |
| `neutral-900` | `#18181B` | Subtle fills |

**Semantic**
| Token | Hex | Usage |
|---|---|---|
| `success-500` | `#22C55E` | Positive PnL, healthy status, confirmations |
| `success-950` | `#0B2013` | Success background tint |
| `warning-500` | `#EAB308` | Approaching threshold, grace period, pending |
| `warning-950` | `#241D06` | Warning background tint |
| `danger-500` | `#EF4444` | Liquidation risk, errors, destructive actions |
| `danger-950` | `#260A0A` | Danger background tint |
| `info-500` | `#3B82F6` | Informational, links, non-critical notices |

**Rule: orange is never used for status.** Health, risk, and success/failure states use the semantic scale exclusively. Orange is reserved for *action and attention*, not *state* — conflating the two is how interfaces end up with orange meaning five different things and thus nothing. A liquidation-risk badge is red, not orange, even though orange is louder; consistency of meaning beats loudness.

**Light mode.** Not an afterthought — institutional users often run light mode in office environments. `bg-canvas` → `#FFFFFF`, `bg-canvas-raised` → `#F7F7F8`, text inverts, accent orange darkens one step (`#EA6A0C` as primary) for AA contrast on white. Both themes ship at launch; theme is a user preference, not a marketing choice.

**Contrast targets.** Body text ≥ 4.5:1 (AA), all numeric/financial data ≥ 7:1 (AAA) — a health factor or a liquidation price is never in a contrast range where "I think it says 1.4" is possible.

### 1.2 Typography scale

Montserrat (headings — geometric, confident, works at large display sizes) / Poppins (UI & body — friendlier at small sizes, excellent number legibility). Both loaded with `font-display: optional` + system fallback stack to avoid layout shift on financial data that must not jump.

**Tabular numerals are mandatory (`font-variant-numeric: tabular-nums`) on every numeric value, no exceptions** — prices, balances, percentages, table cells. Proportional numerals on a balance that updates live is the single most common "this feels janky" bug in fintech UI.

| Token | Family / Weight | Size / Line-height | Usage |
|---|---|---|---|
| `display-xl` | Montserrat 700 | 64px / 72px, -2% tracking | Landing hero only |
| `display-lg` | Montserrat 700 | 48px / 56px, -2% | Landing section headers |
| `heading-1` | Montserrat 600 | 36px / 44px, -1% | Page titles |
| `heading-2` | Montserrat 600 | 28px / 36px | Section headers |
| `heading-3` | Montserrat 600 | 22px / 30px | Card / panel headers |
| `heading-4` | Montserrat 600 | 18px / 26px | Subsection, table group headers |
| `body-lg` | Poppins 400 | 17px / 28px | Landing copy, long-form |
| `body` | Poppins 400 | 15px / 24px | Default UI text |
| `body-sm` | Poppins 400 | 13px / 20px | Secondary text, captions, helper text |
| `label` | Poppins 500 | 13px / 18px, +2% tracking, uppercase optional | Form labels, table headers, eyebrow text |
| `numeric-xl` | Poppins 600, tabular | 40px / 48px | Hero stat (portfolio total, vault APY) |
| `numeric-lg` | Poppins 600, tabular | 28px / 36px | Card primary figure |
| `numeric` | Poppins 500, tabular | 15px / 24px | Table cell figures, inline amounts |
| `numeric-sm` | Poppins 500, tabular | 13px / 20px | Secondary figures, badges |
| `mono` | JetBrains Mono 400 | 13px / 20px | Addresses, hashes, tx IDs — monospace so truncation and comparison are legible |

Scale ratio ~1.25 (major third), collapsed to fewer steps on mobile (§7).

### 1.3 Spacing system

4px base unit, exposed as an 8-step scale so every margin/padding in the product traces to one of these — no arbitrary values in implementation.

`space-1` 4px · `space-2` 8px · `space-3` 12px · `space-4` 16px · `space-5` 24px · `space-6` 32px · `space-8` 48px · `space-10` 64px · `space-12` 96px

Component-internal padding uses `space-3`–`space-5`; section separation uses `space-8`–`space-12`. "Spacious layout" is achieved specifically through generous *section* spacing, not inflated component padding — a card padded like a landing-page hero reads as unfinished, not premium.

### 1.4 Grid system

12-column grid, max content width **1440px**, gutter **24px**, side margin fluid (min 24px mobile, up to ~120px at ultra-wide so content never stretches edge-to-edge on large monitors — a common tell of un-art-directed dashboards).

Dashboard layout: fixed **72px** icon-rail or **256px** expanded sidebar (collapsible) + fluid content area, content area itself grid-constrained to 12 columns with a **1200px** practical max (tables/charts need width; marketing copy does not).

### 1.5 Border radius

Restrained and consistent — sharp enough to read institutional, soft enough to not feel like a terminal.

`radius-sm` 6px (badges, chips, small buttons) · `radius-md` 10px (inputs, buttons, table rows) · `radius-lg` 16px (cards, panels) · `radius-xl` 24px (modals, large feature cards) · `radius-full` (pills, avatars, status dots)

No radius above 24px anywhere. Large soft-rounded cards (30px+) read as consumer/gamified — explicitly in the "avoid" list.

### 1.6 Shadows & elevation

On black, shadows alone barely register — elevation is communicated primarily through **background-lightness steps** (§1.1's canvas/raised/overlay/sunken ladder) with shadow as a secondary cue, mainly for light mode and for anything that floats above content (modals, dropdowns, toasts).

| Token | Value | Usage |
|---|---|---|
| `shadow-sm` | `0 1px 2px rgba(0,0,0,.4)` | Raised cards on dark |
| `shadow-md` | `0 4px 12px rgba(0,0,0,.5)` | Dropdowns, popovers |
| `shadow-lg` | `0 12px 32px rgba(0,0,0,.6)` | Modals |
| `shadow-glow-accent` | `0 0 0 1px rgba(249,115,22,.4), 0 4px 20px rgba(249,115,22,.15)` | Focus state on the single primary CTA only — used sparingly, this is the one place a glow is allowed |

No neon glows on cards, borders, or decorative elements — glow is reserved for the one focus/active state above. This is the explicit boundary against "meme coin aesthetics."

### 1.7 Icons

**Lucide** icon set (already in the repo's dependencies) — geometric, consistent stroke weight, matches the Montserrat/Poppins geometry. Stroke width **1.75px** standard, **2px** at sizes below 20px for legibility. Sizes: 16 / 20 / 24 / 32px, no in-between sizes. Icons are functional, never decorative filler — every icon in the product must be pointable-to as communicating something (direction, category, state), or it's removed.

### 1.8 Buttons

| Variant | Use | Visual |
|---|---|---|
| **Primary** | The one primary action per screen (Borrow, Confirm, Connect Wallet) | Solid `accent-500`, white text, `radius-md`, hover `accent-600`, active scale 0.98 |
| **Secondary** | Alternative actions | 1px `neutral-700` border, transparent fill, white text, hover fills `neutral-900` |
| **Ghost** | Tertiary / low-emphasis (Cancel, table row actions) | No border, `neutral-300` text, hover `neutral-900` background |
| **Destructive** | Withdraw all, close position, revoke | `danger-500` border + text on ghost, solid `danger-500` on confirm step |
| **Icon** | Icon-only actions | 36×36px hit target minimum, `radius-md` |

Sizes: `sm` 32px height · `md` 40px (default) · `lg` 48px (primary landing CTAs, primary transaction confirm). Every button has an explicit **loading state** (spinner replaces label, width preserved via min-width to prevent layout shift) and **disabled state** (40% opacity, no hover, cursor not-allowed) — a disabled primary button must also communicate *why* via adjacent helper text or tooltip, never disabled-and-silent.

### 1.9 Cards

Base card: `bg-canvas-raised`, `radius-lg`, `1px` `neutral-800` border (not shadow-only — a hairline border is what makes a card readable on a pure-black canvas), `space-5` internal padding. Interactive cards (clickable market/pool rows) get a hover state of border → `neutral-700` and a 150ms background lift, never a scale transform (scale-on-hover on a data card reads as gimmicky).

Card anatomy is standardized: **eyebrow label** (`label` token, `neutral-300`) → **primary figure** (`numeric-lg`/`numeric-xl`) → **secondary context row** (change indicator, comparison) → optional **footer action**. Every stat card in the product follows this exact anatomy so the eye learns the pattern once.

### 1.10 Forms & inputs

Text/number input: `bg-canvas-sunken`, `1px` `neutral-800` border, `radius-md`, `space-4` horizontal / `space-3` vertical padding, `body` text. Focus: border → `accent-500`, 1px `accent-400` ring at 20% opacity — deliberately restrained, not the glow reserved for primary CTAs.

**Amount input (the most-used input in the product)** is a distinct component: large `numeric-lg` type, token selector docked right (icon + symbol + chevron), "MAX" affordance docked right of that, USD-equivalent shown as `body-sm` `neutral-300` directly beneath, balance shown top-right of the field ("Balance: 1,204.50 USDC") as a tap-to-fill target. Validation (insufficient balance, below minimum, exceeds cap) renders inline beneath the field in `danger-500`, never as a toast — the error must be spatially at the point of the mistake.

Select/dropdown: same shell as text input, chevron-down icon, opens a `bg-canvas-overlay` panel with `shadow-md`. Toggle/switch: track `neutral-800` → `accent-500` when on, thumb white, 150ms ease. Checkbox/radio: 20px, `radius-sm`/`radius-full` respectively, `accent-500` when checked with a white check glyph, never a filled black-on-black state that fails contrast.

Labels always above the field (never inside-only as a placeholder-doubles-as-label pattern — that pattern loses the label the moment the user types, which is hostile in a financial form). Helper text below in `body-sm` `neutral-300`; error text replaces helper text in `danger-500` with an inline icon.

### 1.11 Tables

The dominant content type in the product (markets, positions, transactions) and therefore the component with the most design investment.

- Row height **56px** default, **44px** "dense" mode (institutional console).
- Header row: `label` token, `neutral-300`, `1px` bottom border `neutral-800`, sticky on scroll.
- Zebra via border, not fill — a hairline `neutral-900` divider between rows, no alternating background (alternating fills on a dark table read noisy; a clean divider is quieter and more premium).
- Row hover: `bg-canvas-overlay` at low opacity, only on interactive (clickable) tables.
- Numeric columns right-aligned, tabular nums, consistent decimal precision within a column (never 2 decimals in one row and 4 in the next for the same metric).
- Sort: chevron indicator in header, active column header in `neutral-0` (others `neutral-300`).
- Sticky first column (asset/market name) on horizontal scroll for mobile/dense tables.
- Row-level status via a **left-edge 2px color bar** (success/warning/danger) rather than a full-row tint — a full-row red tint on a table of positions reads alarmist; a precise edge indicator reads considered.
- Pagination: cursor-based "Load more" for long lists (transactions), numbered pagination only for bounded sets (governance proposals).

### 1.12 Charts

Chart.js (already in repo deps) as the base, restyled to the system — never default Chart.js colors/gridlines.

- Gridlines: `neutral-900`, 1px, horizontal only (vertical gridlines add noise without adding information on time-series).
- Axis labels: `body-sm`, `neutral-300`.
- Line charts (price, TVL, APY history): 2px line, `accent-500` for the primary series, `neutral-500` for comparison/secondary series, gradient fill beneath the primary line fading from `accent-950` at 40% to transparent — the **only** approved gradient use in the entire system, and only ever black-to-orange-tint under a line, never a rainbow or multi-hue gradient.
- Bar charts (volume, utilization): `radius-sm` on bar tops only, `accent-500` for the highlighted/current bar, `neutral-700` for others.
- Health-factor / utilization gauges: semicircular or linear bar with a three-zone background (`success`/`warning`/`danger` bands at low opacity) and a precise pointer/fill showing exact position — the zones give instant read, the exact fill gives precision. Never a single-color bar with no zone context.
- Tooltips: `bg-canvas-overlay`, `shadow-md`, `radius-md`, exact figures with full precision (charts are for pattern, tooltips are for truth).
- Empty/loading chart state: skeleton with a faint animated placeholder curve, never a blank box (§1.14).

### 1.13 Badges, chips, tags

`radius-sm`, `body-sm`/`numeric-sm` text, `space-2`/`space-3` padding, always icon+text when representing a state (never color alone — colorblind-safe by construction).

| Type | Style |
|---|---|
| **Verification tier** (Unverified / Verified / Institutional) | Outline style, tier-specific icon (shield outline → shield check → shield with building), neutral border for Unverified, `accent-400` border+text for Verified, `success-500` for Institutional |
| **Risk/health status** | Filled 10%-opacity semantic background + full-opacity semantic text/icon (Healthy=success, Caution=warning, At Risk=danger) |
| **Market/access tier** (Open / Verified / Institutional) | Same pattern as verification tier, applied to pools/vaults |
| **Transaction status** (Pending / Confirmed / Failed) | Pending = warning with subtle pulse animation, Confirmed = success, Failed = danger |

### 1.14 Loading states

**Skeleton loading, not spinners, for content.** Spinners are reserved for *actions* (button loading, transaction pending). Any area displaying data (cards, tables, charts) shows a skeleton shaped like the eventual content — same dimensions, `neutral-900` base with a subtle 1.5s shimmer sweep at low opacity. This prevents layout shift and, more importantly, never shows a "0" or blank value that could be misread as real data mid-load — a skeleton is unambiguously "not yet data," a zero is ambiguous.

Global page transitions use a **thin top progress bar** in `accent-500` (Linear/Vercel-style), not a full-page spinner — the UI should never fully block on navigation.

### 1.15 Empty states

Every empty state has: an icon (24–32px, `neutral-500`, never decorative illustration — illustrations skew consumer/playful, off-brand here), a one-line explanation in `body`, and where applicable a primary action. Three distinct empty-state registers:
- **Zero-state (never used the feature)** — "You have no open positions. Borrowing against verified collateral starts here." + primary CTA.
- **Filtered-empty (filters produced no results)** — "No markets match these filters." + "Clear filters" ghost button. Never the same copy as zero-state — conflating them makes users think a filter cleared their data.
- **Gated-empty (feature exists but is policy-locked)** — used for unverified users viewing `/app/borrow`: shows what's behind the gate (blurred/dimmed preview of the real screen) with the verification CTA overlaid — sells the destination rather than just blocking it.

### 1.16 Modals, alerts, toasts

**Modals** — `bg-canvas-overlay`, `radius-xl`, `shadow-lg`, max-width 480px (forms/confirmations) or 640px (detailed review, e.g. transaction simulation breakdown), centered, backdrop `rgba(0,0,0,.7)` with blur(4px). Transaction-confirmation modals are the highest-stakes UI in the product (§5) and get a dedicated anatomy in §1.16.1. Modals trap focus, close on `Esc` and backdrop click *except* mid-transaction-signing (no accidental dismissal while a wallet prompt is pending).

**Alerts (inline, persistent)** — banner style, `radius-lg`, left icon, semantic-tinted background at 8% opacity with full-opacity border-left 3px in the same semantic color. Used for account-level persistent conditions: "Your identity credential expires in 12 days," "This position is within 8% of liquidation." Dismissible only if the underlying condition is non-critical; liquidation-risk alerts are not dismissible, only resolvable.

**Toasts** — transient, bottom-right desktop / bottom-center mobile, `bg-canvas-overlay`, `shadow-md`, `radius-md`, auto-dismiss 5s (8s for transaction toasts, which include a block-explorer link and are dismissible but not urgent). Toast stack never exceeds 3 visible; additional toasts queue. Transaction toasts progress through states in place (Submitted → pulsing warning icon; Confirmed → success icon + checkmark animation; Failed → danger icon + "View reason") rather than spawning a new toast per state — one toast, evolving.

**1.16.1 Transaction confirmation modal anatomy** (the trust-critical component):
1. Action title in `heading-3` ("Confirm Borrow")
2. Exact amounts in/out with token icons, `numeric-lg`
3. **Full parameter breakdown** — rate, health factor before → after (shown as a transition, not just the end state), liquidation price before → after, fees, slippage if applicable — every number the user needs to make the decision, none hidden behind a "details" toggle
4. Simulation result banner — green "This transaction will succeed" or red "This transaction will fail: [decoded reason]" computed from a pre-flight simulation (per `ARCHITECTURE.md` §7); **the confirm button is disabled if simulation fails**
5. Primary confirm button, full width, `lg` size
6. Secondary "Edit" / ghost cancel

### 1.17 Accessibility baseline (applies to every component above)
WCAG 2.1 AA minimum, AAA for financial figures. Full keyboard operability — every table row, card, and modal control reachable and actionable via keyboard, with a visible focus ring (`accent-400` at 40%, 2px offset, never `outline: none` without replacement). `prefers-reduced-motion` disables all non-essential animation (§8 marks which animations are essential vs. decorative). Screen-reader live regions announce transaction state changes and balance updates. Color is never the sole carrier of meaning (icons/text always pair with semantic color).

---

## 2. Navigation

Three distinct navigation contexts, matching the trust boundaries in `ARCHITECTURE.md` §12 — public marketing/protocol data, authenticated app, and institutional console are visually related but structurally distinct so a user always knows which "mode" they're in.

### 2.1 Public site nav (marketing, `/markets`, `/risk`, `/governance`, `/developers`)
Fixed top bar, 72px height, `bg-canvas` at 80% opacity with backdrop-blur on scroll (stays legible over content, never fully transparent-then-opaque jank). Logo left. Primary nav center-left: Markets · Risk · Governance · Developers. Right-aligned: theme toggle, "Connect Wallet" (secondary button) always visible — connecting is possible from any public page, not gated behind entering the app.

### 2.2 Authenticated app shell (`/app/*`)
**Left sidebar**, collapsible between 256px (expanded, icon+label) and 72px (rail, icon-only with tooltip on hover). Default expanded on desktop ≥1440px, default collapsed 1024–1439px, hidden entirely on mobile in favor of a bottom tab bar (§7).

Sidebar sections, top to bottom:
1. Logo (click → `/app/dashboard`)
2. Primary nav: Dashboard · Portfolio · Borrow · Lend · Pools · Vaults · RWA
3. Divider
4. BitScore (own nav item, not nested — it's a cross-cutting identity signal, not a sub-feature of any one product)
5. Divider
6. Secondary: Transactions · Notifications (badge with unread count) · Settings
7. Bottom-anchored: network selector (Monad Testnet/Mainnet chip), wallet chip (avatar + truncated address + balance, opens account drawer on click), collapse toggle

**Top bar within the app shell** (not a second nav, a context bar): page title (`heading-2`), breadcrumb for nested pages (e.g. Borrow → Market detail), and right-aligned contextual actions specific to the page (e.g. "New Position" on the borrow page).

**Active state:** left sidebar item gets `accent-500` left-edge 2px bar + icon/text shift to `neutral-0` (from `neutral-300` default) — no filled-background active state, which would compete with the card system's use of raised backgrounds.

### 2.3 Institutional console (`/institution/*`)
Same shell, sidebar swaps to entity-scoped items (Overview · Accounts · Limits · Reporting · API Keys) and the top bar carries an entity switcher if the CVI covers multiple entities. Table density defaults to "dense" (44px rows) throughout — institutional users manage volume, not glanceability.

### 2.4 Mobile navigation
Bottom tab bar, 5 items max (Dashboard, Borrow, Pools, Vaults, More), 56px height, `bg-canvas-raised` with top border, active tab in `accent-500` icon+label. "More" opens a full-screen sheet with the remaining nav items (Lend, RWA, BitScore, Transactions, Notifications, Settings, Institution if applicable). Top bar on mobile collapses to: back/menu icon, page title, wallet avatar — no persistent sidebar.

### 2.5 Command palette (⌘K)
Global, available everywhere in the authenticated app. Search markets, positions, navigate to any page, execute quick actions ("Repay position #4"). This is a deliberate Linear/Vercel-derived pattern — institutional and power users expect keyboard-first navigation, and it materially raises the perceived engineering quality of the product for a modest build cost.

---

## 3. Landing page

Single scrolling page, generous vertical rhythm (`space-12` between major sections minimum), dark canvas throughout — no white marketing-site sections breaking the black identity.

**Hero**
Full-viewport-height (not more — never force scroll to "prove" content exists). Left-aligned on desktop: eyebrow label ("Built on Monad · Powered by Cleanverse"), `display-xl` headline "The Trust Layer for DeFi.", `body-lg` subhead (two lines max — what BitV does, not how), two CTAs (Primary "Launch App," Secondary "Read the Docs"). Right side: a live, real, animated data visualization — not a mockup screenshot, but an actual rendering of protocol data (a stylized health-factor gauge or TVL sparkline pulling live numbers) — this single choice is what separates "premium fintech" from "generic landing page," because it proves the product is real before the user has connected anything. Background: pure black with one extremely subtle radial gradient (orange at <4% opacity, large radius, centered off-screen top-right) — the only gradient permitted on the page, and it must be nearly imperceptible, felt rather than seen.

Below the fold, a thin **live stats strip**: TVL, Active Markets, Verified Users, Total Borrowed — `numeric-lg`, tabular, animated count-up on first viewport entry only (not on every scroll-into-view, which becomes irritating on a long page).

**Features** (grid, 4 cards: Verified Pools, Identity-Based Lending, Yield Vaults, RWA Lending) — icon, `heading-3` title, 2-line description, "Learn more" ghost link. Cards use the standard card component (§1.9), not a bespoke marketing treatment — consistency here is what makes the product feel like one system end to end rather than a marketing site bolted onto an app.

**How it works** — horizontal 4-step process (Connect → Verify Identity → Access Markets → Build BitScore), connected by a thin line with numbered nodes, each node expandable/hoverable for detail. This is the section most responsible for converting a skeptical DeFi-native visitor who's never seen identity-gated lending before — it must make the mechanism legible in ten seconds.

**Why BitV** — three-column comparison: "Traditional DeFi" vs "BitV" vs (implicitly) "TradFi," showing the specific tradeoffs BitV resolves (anonymous↔over-collateralized-only vs. verified↔under-collateralized access), stated factually, no hype copy.

**Why Monad** — technical credibility section: parallel execution, sub-second finality, low fees — each stated with the *product consequence* ("fees low enough that partial liquidations protect your position instead of closing it entirely"), never the raw spec alone. Logo lockup with Monad, link to Monad docs.

**Why Cleanverse** — same treatment: what CVI/CVA are, why bank-verified identity beats wallet-only reputation, explicit statement that BitV never stores the underlying PII (directly reinforces trust). Logo lockup with Cleanverse.

**Security** — audit firm logos (once real), bug bounty program summary + link, link to `/risk` transparency dashboard, and the "honest risk statement" language from `ARCHITECTURE.md` §21.3 rendered plainly — a security section that admits under-collateralized lending carries real risk, with the specific bounding mechanisms named, reads as *more* credible to the institutional audience than a section that claims zero risk.

**FAQ** — accordion, `radius-lg` items, single-open (accordion, not all-expand) to keep the page scannable. Categories: Getting started, Identity & CVI, BitScore, Risk & Liquidation, Institutional.

**Footer** — four columns (Product, Developers, Company, Legal) + social links + network status indicator (small green dot + "All systems operational," linking to `/status`) + copyright. Footer is dense and information-rich by design — it's where a diligencing user goes looking for the audit report, the contract registry, and the legal disclosures, and all three must be one click away.

---

## 4. Dashboard (authenticated app screens)

Every screen below follows the "what changed, what's at risk, what can I do" ordering principle from the Design Principles section.

### 4.1 Overview (`/app/dashboard`)
Landing screen post-auth. Top row: three hero stat cards (Net Worth, Net APY, Health Factor — the last using the gauge component from §1.12, colored by zone). Below: **Alerts rail** (only rendered if non-empty — no "no alerts" filler card) surfacing anything requiring attention (approaching liquidation, credential expiring, credit line maturing) using the persistent-alert component (§1.16), most severe first. Then a two-column layout: left — Portfolio composition (donut chart + legend table of positions across all products), right — BitScore summary card (score, trend sparkline, one-line "why," link to full `/app/bitscore`). Bottom: Recent Activity table (last 5 transactions, "View all" → `/app/history`).

### 4.2 Portfolio (`/app/portfolio`)
Cross-product position table — every open position (lending, borrowing, LP, vault, RWA) in one sortable/filterable table with columns: Product, Asset, Amount, Value, APY/Rate, Health (if applicable), Actions. Filter chips above the table (All / Lending / Borrowing / Pools / Vaults / RWA). Row expand reveals a mini-detail panel in place (avoids full navigation for a quick check) with a "Manage" button linking to the full position screen. Above the table: portfolio value chart (time-range selector: 24h/7d/30d/90d/All) showing total value over time, annotated with deposit/withdraw event markers on the line.

### 4.3 BitScore (`/app/bitscore`)
The most identity-forward screen in the product, designed to make an opaque credit-scoring system feel legible rather than algorithmic-and-scary. Hero: large score number (`numeric-xl`, custom oversized treatment beyond even the standard scale for this one number — it's the emotional centerpiece of the screen) inside a radial progress ring, tier label below (e.g. "Established"), trend indicator (+12 this month). **Factor breakdown** — horizontal bar per factor (Repayment History, Utilization, Tenure, Identity Tier, Collateral Quality) each showing its weight and current contribution, matching `ARCHITECTURE.md` §16.1 exactly — this is the explainability requirement made visual. **History** — line chart of score over time with event annotations (repayment, tier change) as markers on the line, hoverable for detail. **Improvement path** — a card listing concrete next actions ("Maintain on-time repayments for 30 more days to reach Tier 3") rather than generic advice. **Dispute** — ghost link to the dispute flow, low-emphasis but present, satisfying the explainability/appeal requirement from the architecture without cluttering the primary view.

### 4.4 Lending (`/app/lend`)
Market list (table): Asset, Total Supplied, Supply APY, Utilization (mini bar), Access Tier badge, action column. Toggle: "All markets" / "My positions." Clicking a row opens the market detail as a slide-over panel (not full navigation) for quick supply/withdraw, with a "View full market" link for the complete `/markets/lending/[id]` page (rate history chart, full parameters, oracle info).

### 4.5 Borrowing (`/app/borrow`)
Two-mode screen, tab-switched: **Collateralized** and **Credit Line** (the latter locked with the gated-empty pattern §1.15 if BitScore threshold unmet — shown, not hidden, with the exact threshold and current score so the path forward is explicit). Collateralized: standard borrow market list, same anatomy as 4.4. Credit Line: card-based (not table) showing limit, drawn amount as a filled bar against the limit, rate, next payment due, with Draw/Repay actions inline. Active positions list below with health-factor column using the gauge treatment inline in the table row (a compact horizontal version of §1.12's gauge).

### 4.6 Liquidity Pools (`/app/pools`)
Pool list table: Pair (dual token icon), Access Tier badge, TVL, Volume 24h, Fee APR, your liquidity (if any). "Provide Liquidity" opens a dedicated flow (§5.7), not a modal — range selection needs real screen space. "My Positions" tab shows LP position cards with a mini range-visualization (current price marker against the position's set range, in/out-of-range state colored accordingly) plus accrued fees and a claim action.

### 4.7 Yield Vaults (`/app/vaults`)
Vault cards (not a table — vaults are fewer in number and benefit from more visual weight per item): strategy name, asset, APY (`numeric-lg`), capacity bar (filled/total, disabled Deposit if full), access tier badge, TVL. Detail view on click: strategy description in plain language, historical APY chart, fee structure, withdrawal queue status if applicable (shown proactively — "Withdrawals from this vault may take up to 48h due to strategy liquidity" as a persistent inline notice, not discovered at withdrawal time).

### 4.8 Transactions (`/app/history`)
Dense table, all products unified: Date, Type (icon+label), Asset, Amount, Status badge, Tx hash (mono, truncated, copy-on-click + explorer link). Filters: date range, product, status. Export action (CSV/PDF, ties to compliance export in architecture §10) top-right. Infinite scroll / "load more," not pagination — transaction history is naturally chronological and users rarely jump to "page 14."

### 4.9 Notifications (`/app/notifications` or a slide-over drawer, not a full page, given typical usage patterns)
Grouped by recency (Today / This week / Earlier), each item: icon by category (risk/warning icon for liquidation alerts, info icon for governance, success icon for confirmations), one-line description, timestamp, unread state as a left accent dot. Settings gear top-right → deep-links to `/app/settings#notifications`. Critical items (liquidation risk) get a persistent variant that also appears as a dashboard alert (§4.1) — never notification-only for something that can cost the user money.

### 4.10 Settings (`/app/settings`)
Tabbed single page: **Profile** (display preferences, theme), **Identity** (CVI status card — tier, claims summary, expiry, refresh/renew action, revocation notice if applicable — mirrors `ARCHITECTURE.md` §12 states exactly), **Sub-accounts** (institutional only — operator list, add/revoke, per-operator limits), **Notifications** (channel toggles: in-app, email, per-category granularity — liquidation alerts cannot be fully disabled, only the channel changed, since that's a safety-critical notification), **Security** (connected wallets, session keys, active sessions with revoke), **API** (developer keys, institutional only).

---

## 5. User flows

Every flow below follows the transaction lifecycle from `ARCHITECTURE.md` §7 (build → simulate → present → sign → submit → confirm) wherever it involves a write. Steps are UI states, not necessarily separate pages.

### 5.1 Wallet connection
1. "Connect Wallet" (available from any page, public or app) opens a modal listing connectors (Injected/MetaMask, WalletConnect, Coinbase, Safe, Embedded/email) as a clean icon+label list, no bespoke per-wallet branding chaos.
2. Connector-specific flow proceeds (QR for WalletConnect, popup for injected, email OTP for embedded).
3. On connect: chain check — if wrong network, a single-step "Switch to Monad" prompt (not a silent auto-switch, which surprises users) — approve in wallet.
4. Modal closes, sidebar wallet chip populates (avatar, truncated address, balance), toast confirms "Wallet connected."
5. If the user then attempts any gated action without a credential, they enter 5.2 directly from that action's entry point.

### 5.2 Identity verification (CVI)
1. Triggered contextually — user attempts Borrow/Verified-Pool/Vault action without a credential. Never forced immediately on connect (browsing stays frictionless per `ARCHITECTURE.md` §5.1).
2. **Interstitial screen** (not a modal — this deserves full attention): explains what CVI is in plain language, exactly what data is involved, why it's required, and that BitV never stores the underlying documents. Primary CTA "Verify with Cleanverse," secondary "Learn more" → FAQ anchor.
3. Deep-link to Cleanverse's onboarding (external, clearly labeled "You're leaving BitV" micro-copy so the handoff isn't jarring or mistaken for phishing) with a return URL.
4. On return: **pending state** screen — "Verification submitted, typically takes X" with a status indicator, polling in background. User can navigate away; a persistent (dismissible-but-recurring) banner shows verification-pending status until resolved.
5. On resolution: success toast + confetti-free simple checkmark animation on the identity badge (no celebratory over-animation — this is a compliance action, not a game achievement), user is returned to the original intended action, which now proceeds.
6. Failure/rejected path: clear explanation of what to do next (retry, contact support), never a dead end.

### 5.3 Deposit (supply to lending market)
1. From market row or detail page, "Supply" opens the amount-input pattern (§1.10) in a modal.
2. Amount entry with MAX, live USD equivalent, live projected new supply-APY-earned figure.
3. If first interaction with this asset: approval step shown as step 1 of 2 in the modal (progress dots), auto-advancing to deposit after approval confirms — EIP-7702 batched single-signature where the wallet supports it, explicit two-step otherwise, always visible which step is active.
4. Confirmation modal (§1.16.1): amount, new position size, projected earnings, simulation result.
5. Sign → submit → optimistic "Depositing..." state on the position row → confirmed → toast + position row updates with the new balance animating in (number count-up from old to new value, 400ms, the one place a number animates because the change is real and just-occurred).

### 5.4 Withdraw
1. From position row, "Withdraw" — amount input pre-filled to full available amount (most withdrawals are full withdrawals; partial requires editing down, which is the less common case and shouldn't be the default friction).
2. If withdrawal would affect health factor (shared collateral), a live-updating health-factor preview appears in the modal immediately — this is a case where the risk must be shown before, not after.
3. If below a safety margin, input is soft-blocked with inline warning and a "Max safe withdrawal" quick-fill suggestion rather than only a hard error.
4. Standard confirm → sign → submit → confirm cycle.

### 5.5 Borrow
1. From market or credit-line screen, "Borrow" opens a dedicated flow (not just a modal, given the complexity) — full slide-over panel.
2. Step 1: Select collateral (if not already posted) — asset selector with current wallet balance and the resulting LTV/health impact previewed live as amount changes.
3. Step 2: Select borrow amount — same live health-factor and liquidation-price preview, plus rate (with identity-tier discount called out explicitly: "Your BitScore tier gives you a 0.8% rate discount" as a small `success-500` inline note — surfacing the identity benefit at the exact moment it's earned).
4. Step 3: Review — full confirmation modal per §1.16.1: collateral posted, amount borrowed, rate, health factor before→after, liquidation price before→after, fees.
5. Sign → submit → confirm. Landing state: redirected to the new position detail, not back to the market list — the user's attention belongs on the thing they just created.

### 5.6 Repay
1. From position detail, "Repay" — amount input with MAX (full repay) prominently offered alongside partial.
2. Live preview of resulting health factor and, for credit lines, remaining limit and next-due-date shift.
3. Confirm → sign → submit → confirm. On full repayment: position moves from "Active" to a brief "Closed" success state before leaving the position list, with a summary (total interest paid, duration) — a small moment of closure rather than the row just vanishing.

### 5.7 Join pool (provide liquidity)
1. Full dedicated page (not modal — range selection is spatial and needs room), reached from "Provide Liquidity."
2. Token pair selection (if not pre-selected from a specific pool).
3. **Range selector**: visual price-range chart with draggable min/max handles over the current price and historical distribution, plus preset options ("Full range," "Conservative ±10%," "Active ±2%") for users who don't want to manually set ticks.
4. Deposit amounts for both tokens, auto-balanced based on range and current price, with a clear note on which side is currently more heavily weighted.
5. Projected fee APR estimate based on range width and historical volume (explicitly labeled as an estimate, not a guarantee — no implied promise).
6. Confirm (approval step(s) as in 5.3) → sign → submit → confirm → redirected to the new LP position card with the range visualization live.

### 5.8 Stake (vault deposit)
1. From vault card, "Deposit" — amount input, live share-price and projected value shown.
2. If vault has a withdrawal queue, this is disclosed inline in the deposit modal itself ("Deposits into this vault are subject to a withdrawal queue on exit — typical wait: X"), not just on the vault detail page — a commitment the user is making needs to be visible at the moment of commitment.
3. Confirm → sign → submit → confirm → position appears in `/app/portfolio` and the vault's "My Position" state.

### 5.9 Claim rewards
1. Wherever rewards accrue (LP fees, vault yield if distributed rather than auto-compounded), a persistent "Claimable: $X" chip appears on the relevant position card/row — always visible when non-zero, never requiring navigation to discover.
2. "Claim" — for small amounts, a single-click flow with no separate confirmation modal (low-stakes, high-frequency action; forcing a full confirmation modal on every small fee claim is friction without corresponding safety value). For claims above a configurable threshold, the standard confirmation modal applies.
3. Sign → submit → confirm → claimed amount briefly shown as a "+$X" floating micro-animation near the claim button (400ms, essential-tier animation per §8) before settling into the updated balance.

---

## 6. Component inventory (complete, implementation-ready)

Organized by the layer they belong to, matching `ARCHITECTURE.md` §6's `components/` vs `features/` split.

**Foundation / primitives (shadcn-based, system-themed)**
Button (5 variants × 3 sizes) · IconButton · Input (text/number) · AmountInput · Select · MultiSelect · Combobox · Textarea · Checkbox · RadioGroup · Switch · Slider (for range/LTV selection) · Tabs · Accordion · Tooltip · Popover · DropdownMenu · Dialog/Modal · Sheet/SlideOver · Toast · Alert (persistent) · Badge · Chip · Avatar · Skeleton · ProgressBar · Separator · Card (base) · Table (base) · Pagination

**Data display**
StatCard (per §1.9 anatomy) · DataTable (sortable, filterable, with row-status edge indicator) · Sparkline · LineChart · BarChart · DonutChart · Gauge (health/utilization, semicircular + linear variants) · RangeVisualizer (LP position range chart) · CountUpNumber · TrendIndicator (arrow + % + color) · EmptyState (3 registers per §1.15) · ErrorState

**Identity & trust**
CVIStatusBadge · VerificationTierChip · VerificationGate (wraps gated content, renders blurred-preview empty state or children) · IdentityVerificationInterstitial · CredentialExpiryAlert · BitScoreRing · BitScoreFactorBar · SanctionsFreezeNotice

**Transaction / wallet**
WalletConnectModal · WalletChip (sidebar) · AccountDrawer · NetworkSelector · NetworkSwitchPrompt · TransactionConfirmModal (per §1.16.1) · TransactionSimulationBanner · TransactionToast (multi-state) · TransactionStatusBadge · GasEstimateDisplay · ApprovalStepIndicator · TxHashDisplay (mono + copy + explorer link)

**Risk**
HealthFactorGauge (inline table variant + full card variant) · LiquidationPriceDisplay · HealthFactorPreview (before→after, used in every write-flow confirm step) · ExposureRing · OracleStatusIndicator · CircuitBreakerBanner

**Market / position**
MarketRow · MarketDetailPanel · PositionCard · PositionTable · AccessTierBadge · APYDisplay (with identity-discount inline note) · CapacityBar (vault/market caps) · RangeSelector (LP) · WithdrawalQueueNotice · CreditLineCard (limit bar, draw/repay)

**Navigation & shell**
Sidebar (expanded/rail/mobile-hidden states) · TopBar/ContextBar · BottomTabBar (mobile) · CommandPalette · Breadcrumb · NotificationDrawer · ThemeToggle

**Layout**
PageHeader · Section · TwoColumnLayout · GridLayout · SlideOverPanel · FilterBar · SearchInput

---

## 7. Responsive design

Breakpoints: `sm` 640px · `md` 768px · `lg` 1024px · `xl` 1280px · `2xl` 1440px (content max).

**Desktop (≥1024px).** Full sidebar (expanded ≥1440px, rail 1024–1439px), multi-column dashboards, tables shown in full with all columns, slide-over panels at 480–640px width leaving context visible behind, modals centered at fixed max-width. This is the primary design target — institutional users work on desktop, and dense financial tables genuinely need the horizontal space.

**Tablet (768–1023px).** Sidebar collapses to rail-only or hidden-behind-hamburger depending on orientation; dashboard grids drop from 3–4 columns to 2; tables switch to horizontal scroll with the first (identifying) column sticky rather than dropping columns, which would hide information silently; slide-over panels become full-height but not full-width (still leaves a context sliver); modals scale down padding but keep max-width logic.

**Mobile (<768px).** Bottom tab bar replaces sidebar entirely (§2.4); all multi-column layouts collapse to single column, cards stack; tables convert to a **card-list pattern** for anything beyond 3–4 columns — each row becomes a compact card with a primary line (asset + primary figure) and a secondary line (2–3 key stats), tapping expands full detail — a literal responsive table (squeezed columns, tiny text) is explicitly rejected as unreadable and untappable; slide-over panels become full-screen sheets; modals become bottom sheets (easier one-handed reach and dismissal than a centered dialog); the amount-input component gets a larger touch-optimized numeric keypad affordance; charts simplify (fewer gridlines, larger touch targets on data points, tooltip-on-tap instead of hover).

**Typography scaling.** Display/heading sizes step down one tier per breakpoint below `lg` (e.g. `display-xl` 64px desktop → 40px mobile) to maintain proportion rather than simply reflowing at fixed size; body and numeric scales stay constant across breakpoints since financial figures should read at consistent size regardless of device — shrinking a balance on mobile is a readability regression users notice immediately.

**Touch targets.** Minimum 44×44px on any interactive element on touch breakpoints, spacing between adjacent tappable elements minimum `space-3` (12px) to prevent mis-taps on financial actions — a fat-fingered wrong-token selection is a real-money mistake, not just an inconvenience.

**Institutional console on mobile.** Explicitly de-prioritized — the console remains functional (read access, approvals) but complex configuration (limits, sub-account management) shows a "best experienced on desktop" notice rather than cramming a management-heavy UI into a phone screen. This is a considered scope decision, not an oversight: forcing full parity here would degrade the desktop experience to accommodate a use case that essentially never occurs in practice.

---

## 8. Animation & micro-interaction guidelines

Governing rule: **animation confirms state change, it never creates delay.** Every duration below is a maximum; nothing in the product should feel like it's waiting on an animation to finish before becoming usable.

**Timing scale.** `duration-instant` 100ms (hover states, focus rings) · `duration-fast` 150ms (button press, toggle, card hover) · `duration-base` 200ms (panel/modal open, dropdown) · `duration-slow` 400ms (number count-up, page-level transitions) · nothing in the product exceeds 400ms. Easing: `ease-out` for entrances (things arriving should decelerate, feels responsive), `ease-in` for exits (things leaving should accelerate, feels quick to get out of the way), never a bouncy/spring easing on financial UI — bounce reads playful/gamified, explicitly off-brand.

**Essential (state-communicating) animations — always on, not affected by "reduce motion" beyond speed reduction:**
- Number count-up/count-down when a real value changes (balance after deposit, score after update) — 400ms, ease-out. Never on initial page load (which would misrepresent zero→value as a "gain").
- Health-factor gauge needle/fill transitioning between before/after states in confirmation modals — 300ms, makes the *consequence* of an action visible rather than just the end state.
- Transaction toast state evolution (pending → confirmed/failed) — icon crossfade + subtle scale pulse, 200ms.
- Skeleton shimmer during loading (§1.14).
- Focus ring appearance — instant, no delay ever, for accessibility.

**Polish (decorative-adjacent, subject to `prefers-reduced-motion`):**
- Card hover: border-color transition + 2px translateY lift, 150ms.
- Button press: scale to 0.98, 100ms.
- Sidebar expand/collapse: width + label-opacity transition, 200ms ease-out.
- Modal/sheet entrance: opacity + 8px translateY, 200ms ease-out; exit reversed at 150ms.
- Dropdown/popover: opacity + 4px translateY + scale from 0.98, 150ms.
- Page-level route transitions: thin top progress bar only (§1.14) — no full-page fade/slide, which on a data-dense app just delays perceived readiness.
- Verification success checkmark: single draw-on stroke animation, 400ms, once.
- Claim-reward micro-animation (§5.9): floating "+$X," 400ms ease-out, fades and settles.

**Explicitly rejected:** confetti/celebration effects, particle effects, bouncing/spring physics, auto-playing looping animations (ticker-style scrolling logos, pulsing CTAs beyond a single subtle pending-state pulse), parallax scrolling on the landing page, any animation on a number that hasn't actually changed. These are the concrete expressions of "avoid gamified interfaces" — each is a specific pattern common in consumer crypto products that BitV's institutional positioning requires opting out of.

**Chart animations.** Initial render: bars/lines draw in once, 400ms, on first mount only — never re-animate on every data refresh (a live-updating chart that redraws from zero every poll interval is distracting and misrepresents continuity). Data updates after initial render: values interpolate smoothly to new positions without a full redraw.

---

## 9. Complete screen inventory

Cross-referenced to `ARCHITECTURE.md` §4 sitemap; this is the design-side checklist for build sequencing.

**Public / marketing**
1. Landing (`/`)
2. Markets directory (`/markets`)
3. Lending market detail (`/markets/lending/[id]`)
4. Pool detail (`/markets/pools/[id]`)
5. Vault detail (`/markets/vaults/[id]`)
6. RWA asset detail (`/markets/rwa/[id]`)
7. Risk transparency — parameters (`/risk/parameters`)
8. Risk transparency — oracles (`/risk/oracles`)
9. Risk transparency — exposure (`/risk/exposure`)
10. Risk transparency — audits (`/risk/audits`)
11. Governance proposals list (`/governance/proposals`)
12. Governance proposal detail (`/governance/proposals/[id]`)
13. Governance parameters (`/governance/parameters`)
14. Governance treasury (`/governance/treasury`)
15. Developers hub (`/developers`)
16. Developers docs / SDK / API reference (`/developers/docs`, `/sdk`, `/api`)
17. Contract registry (`/developers/contracts`)
18. Legal (terms, privacy, disclosures) (`/legal`)
19. Status page (`/status`)

**Authenticated app**
20. Dashboard / Overview (`/app/dashboard`)
21. Portfolio (`/app/portfolio`)
22. BitScore (`/app/bitscore`)
23. Identity status (within Settings, or `/app/identity`)
24. Lend (`/app/lend`)
25. Borrow — collateralized (`/app/borrow`)
26. Borrow — new position flow (`/app/borrow/new`)
27. Borrow — position detail/manage (`/app/borrow/[positionId]`)
28. Pools list (`/app/pools`)
29. Provide liquidity flow (`/app/pools/[id]/provide`)
30. LP positions (`/app/pools/positions`)
31. Vaults list (`/app/vaults`)
32. Vault deposit/withdraw (`/app/vaults/[id]/deposit`)
33. RWA originate flow (`/app/rwa/originate`)
34. RWA deal detail (`/app/rwa/[dealId]`)
35. Transaction history (`/app/history`)
36. Notifications (drawer or `/app/notifications`)
37. Settings — Profile
38. Settings — Identity
39. Settings — Sub-accounts
40. Settings — Notifications
41. Settings — Security
42. Settings — API (institutional)

**Institutional console**
43. Institution overview (`/institution/overview`)
44. Sub-account management (`/institution/accounts`)
45. Internal limits config (`/institution/limits`)
46. Reporting/exports (`/institution/reporting`)
47. API key management (`/institution/api-keys`)

**Liquidation**
48. Liquidation opportunities (`/liquidate/opportunities`)
49. Liquidation auctions (`/liquidate/auctions`)

**Cross-cutting states (not standalone routes, but required design states for every relevant screen)**
50. Wallet-not-connected state
51. Identity-verification interstitial
52. Identity-verification pending state
53. Gated/locked feature preview (blurred content + CTA)
54. Global 404
55. Global error boundary
56. Maintenance/paused-market state

**Total: 49 routed screens + 7 cross-cutting states = 56 design surfaces.**

---

## 10. Component checklist (build-sequencing form)

Grouped in the order they unblock downstream screens — matches `ARCHITECTURE.md` §24 build ordering philosophy (foundation before feature).

**Phase 1 — Tokens & primitives (blocks everything)**
☐ Color tokens (dark + light) ☐ Type scale ☐ Spacing scale ☐ Radius scale ☐ Shadow scale ☐ Icon set integration ☐ Button (all variants/sizes) ☐ Input/AmountInput ☐ Select/Combobox ☐ Checkbox/Radio/Switch ☐ Card (base) ☐ Badge/Chip ☐ Tooltip/Popover ☐ Skeleton

**Phase 2 — Shell & navigation (blocks all authenticated screens)**
☐ Sidebar (all states) ☐ TopBar/ContextBar ☐ BottomTabBar ☐ CommandPalette ☐ ThemeToggle ☐ WalletChip ☐ NetworkSelector ☐ Breadcrumb

**Phase 3 — Trust & identity (blocks every gated screen)**
☐ WalletConnectModal ☐ VerificationGate ☐ IdentityVerificationInterstitial ☐ CVIStatusBadge ☐ VerificationTierChip ☐ CredentialExpiryAlert ☐ SanctionsFreezeNotice ☐ EmptyState (all 3 registers)

**Phase 4 — Transaction pipeline (blocks every write flow)**
☐ TransactionConfirmModal ☐ TransactionSimulationBanner ☐ TransactionToast ☐ ApprovalStepIndicator ☐ HealthFactorPreview ☐ GasEstimateDisplay ☐ TxHashDisplay

**Phase 5 — Data display (blocks all market/position screens)**
☐ DataTable ☐ StatCard ☐ LineChart/BarChart/DonutChart ☐ Gauge (semicircular + linear) ☐ Sparkline ☐ CountUpNumber ☐ TrendIndicator

**Phase 6 — Feature components**
☐ MarketRow/MarketDetailPanel ☐ PositionCard/PositionTable ☐ CreditLineCard ☐ RangeSelector/RangeVisualizer ☐ CapacityBar ☐ WithdrawalQueueNotice ☐ BitScoreRing/BitScoreFactorBar ☐ AccessTierBadge ☐ APYDisplay

**Phase 7 — Layout & polish**
☐ SlideOverPanel ☐ FilterBar ☐ NotificationDrawer ☐ PageHeader/Section layouts ☐ Full animation pass per §8 ☐ Responsive card-list table fallback (mobile) ☐ Accessibility audit pass (keyboard, contrast, screen reader) across all Phase 1–6 components

This ordering means a functional, on-brand, keyboard-accessible shell with working wallet connection and identity gating exists before a single market screen is built — the trust layer is visually real before the financial features are, which matches the product's own thesis.
