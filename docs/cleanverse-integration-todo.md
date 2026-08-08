# Cleanverse Integration — Information Still Required

Per the project's core rule: use the official Cleanverse documentation as
the source of truth, and do not invent APIs, SDKs, endpoints, contracts, or
terminology. **This session still could not inspect the official docs
content** — `https://docs.cleanverse.com/` was located via web search but
direct fetch is blocked by this sandbox's network egress policy
(`EGRESS_BLOCKED: docs.cleanverse.com`). `services/cleanverse/` remains
empty stubs; nothing below has been verified against primary source text.

## What a web search surfaced (UNVERIFIED — do not implement against this)

Search result snippets (not the docs themselves) describe Cleanverse as "a
compliance-native rules layer that interlocks verified identity and
verified assets on every value transfer," referencing:

- **CVI** — "Cleanverse Verified Identity"
- **CVA** — "Cleanverse Verified Asset"
- An "API v3" with a sandbox environment separate from production credentials

These terms are plausible but **unconfirmed** — they come from search-result
summaries, not a fetched page, so exact field names, endpoint paths, and
semantics are unknown. Do not use "CVI"/"CVA" in code or types until this is
confirmed directly from `docs.cleanverse.com`.

## Exact checklist — required before implementation

1. **Identity primitive** — What object does Cleanverse actually issue for
   verified identity (is "CVI" the real term)? What does it contain?
2. **Verified asset primitive** — What is the real "verified asset" object
   (is "CVA" the real term)? How does it attach to an address/identity?
3. **Authentication method** — API key, signed request, OAuth, on-chain
   attestation check — the literal mechanism, header names, token format.
4. **API / SDK** — Is there an official TypeScript/JS SDK (package name,
   registry), a REST API (base URL, versioning — "v3" per search result is
   unconfirmed), a subgraph, or on-chain contracts to read directly?
5. **Required endpoints** — Exact paths/methods needed for: checking a
   user's identity verification status, checking asset verification status,
   initiating verification (if BitV triggers it vs. reading existing state).
6. **Request format** — Payload shape, required headers, content type.
7. **Response format** — Success and error payload shapes, status codes.
8. **Verification flow (identity)** — Literal step-by-step: what does a BitV
   user do, what does BitV call, what does Cleanverse return, in what order.
9. **Verification flow (assets)** — Same, for verified-asset attestation.
10. **Network requirements** — Is this an HTTP API call from a backend only,
    or does it also require an on-chain read/write on a specific network?
    Sandbox vs. production environment endpoints/hostnames.
11. **Environment variables** — Exact names Cleanverse's SDK/API expects
    (current `.env.example` placeholders `CLEANVERSE_API_KEY` /
    `CLEANVERSE_API_BASE_URL` are BitV-side guesses, not confirmed
    Cleanverse variable names).
12. **Error states** — What errors/status codes Cleanverse returns for
    unverified identity, unverified asset, expired verification, rate
    limits, invalid auth, etc., so BitV can model them without inventing
    behavior.
13. **Webhook / event requirements** — Does Cleanverse push
    verification-status changes via webhook, or is it poll/read-only from
    BitV's side? If webhooks exist: payload shape, signature verification
    method, retry semantics.

## Terminology mapping

Once confirmed, preserve Cleanverse's official terms in implementation code
(types, function names, code comments) while keeping BitV's product
language ("BitScore," "identity-gated," etc.) in user-facing copy — per the
project's core instruction not to invent or blur Cleanverse's own
terminology.

`services/cleanverse/types.ts` and `services/cleanverse/client.ts` stay
empty stubs (`Record<string, never>` placeholder types, throwing client
methods) until this checklist is resolved with citations to the actual
fetched documentation, not search summaries.
