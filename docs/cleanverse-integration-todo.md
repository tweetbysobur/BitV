# Cleanverse Integration — Remaining Open Items

**Most of this checklist is now resolved.** As of Build 02.1, the user
provided the two official Cleanverse PDFs directly (`docs.cleanverse.com`
itself remains network-blocked in every sandbox this project has run
in — confirmed repeatedly, including via raw `curl`, unaffected by access
codes since the block is at the network layer):

1. "Cleanverse Compliance Protocol (CCP) Integration Guide (For CVI
   Compliance Validator) V2" — resolves the `IAPassComplianceValidator`
   interface, `RuleV2` fields/types/semantics, Single-Contract Mode vs.
   Factory Mode, and the validator registration API.
2. "Cleanverse Compliance Protocol (CCP) CVA Integration Guide" —
   resolves CVA issuance (`IComplianceRule`/`IATokenPolicy`), the CVA
   Launch/Register APIs, and the "automatic compliance" mechanism.

See `docs/cleanverse-integration.md` for the full spec built from these.
The earlier "CVI"/"CVA" terminology that came only from web-search
snippets is now confirmed correct by these primary sources.

## Still open (genuinely not covered by either PDF)

1. **CVI issuance/verification flow** — how a wallet actually obtains a
   CVI (the user-facing KYC flow) isn't in either guide; both start from
   "the user already has a CVI."
2. **CVI expiration/revocation behavior** — not specified.
3. **Off-chain identity-status lookup API** — no endpoint for "does this
   address have a CVI, and what's its current group/tier" was given;
   only the on-chain `complianceVerify` (yes/no against a specific pool's
   rules) is confirmed.
4. **Validator's deployed address on Monad Testnet** — not given. BitV
   cannot register a contract or call `complianceVerify` for real without
   this.
5. **Full endpoint paths** for: Query Apply Status API, Query Supported
   CVA List, Add CVA Rule API — referenced by name only in the CVA guide,
   no path given.
6. **`api-id` / API key provisioning process** — how BitV would actually
   obtain Cleanverse API credentials isn't described.
7. **AES/CBC/PKCS5Padding key management detail** for the Launch CVA API
   (key source, IV handling) — the algorithm is named, implementation
   detail isn't.
8. **Validator/CVA events** — neither guide lists emitted events.
9. **Pause/freeze function signatures** — the CVI guide's overview
   mentions the validator can "pause pools or freeze accounts (emergency
   risk control)," but §3.2's interface list doesn't include those
   functions' signatures.

None of the above block Build 02's compliance-architecture milestone
(all covered functionality is implemented). They block: (a) actually
registering a BitV contract with a real validator, (b) building any
identity-status UI beyond static states, (c) BitV ever issuing its own
CVA token.

## Terminology (confirmed, not to be second-guessed)

- **CVI** = Cleanverse Verified Identity (identity primitive)
- **CVA** = Cleanverse Verified Asset (compliant-token primitive, separate
  contract/interface from the CVI validator)
- **RuleV2** = the compliance policy struct shared by both systems
- **BitScore** = BitV's own risk layer, explicitly not a Cleanverse term
  or primitive — keep it out of any code/types that mirror Cleanverse's
  interfaces.
