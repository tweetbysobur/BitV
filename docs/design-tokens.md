# BitV Design Tokens

Source of truth: `app/globals.css` (CSS variables) and `tailwind.config.ts`
(Tailwind mapping). This file documents intent; the CSS is authoritative.

## Brand

- Primary: Black
- Accent: Orange (`--accent`, HSL `24 95% 53%`)
- Direction: premium fintech, institutional DeFi, minimal, high-contrast,
  clean, professional, modern
- Avoid: meme-coin aesthetics, gradients, neon, clutter, gamified UI

## Typography

- Primary (headings): Poppins — `--font-poppins`, `font-heading`
- Secondary (body): Montserrat — `--font-montserrat`, `font-body`

Loaded via `next/font/google` in `lib/fonts.ts` and applied as CSS variables
on `<html>` in `app/layout.tsx`.

## Color tokens

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--background` | white | near-black | page background |
| `--foreground` | near-black | near-white | body text |
| `--card` | white | dark gray | surfaces |
| `--border` | light gray | dark gray | dividers, outlines |
| `--muted` / `--muted-foreground` | gray tones | gray tones | secondary content |
| `--primary` / `--primary-foreground` | black/white | white/black | primary actions |
| `--accent` / `--accent-foreground` | orange/black | orange/black | brand accent, CTAs |

No gradient tokens are defined by design.
