# Cleanverse Integration — Information Still Required

Per the project's core rule: use the official Cleanverse documentation as
the source of truth, and do not invent APIs, SDKs, endpoints, contracts, or
terminology. This session did not have access to fetch or inspect
Cleanverse's official documentation, so the integration boundary
(`services/cleanverse/`) was created as empty, throwing stubs only.

Before any real Cleanverse implementation work, the following must be
confirmed from the actual docs:

1. **Identity primitives** — What object/credential does Cleanverse issue
   for verified identity? What is it actually called in their docs?
2. **Verified asset primitives** — What is the actual primitive for a
   "verified asset" in Cleanverse's model, and how does it attach to an
   address or identity?
3. **SDKs / APIs available** — Is there an official TypeScript/JS SDK, a
   REST API, a subgraph, on-chain contracts to read directly, or some
   combination? What are the real package names / endpoints?
4. **Authentication requirements** — API keys, signed messages, OAuth,
   on-chain attestation checks — whatever Cleanverse actually requires.
5. **Integration flow** — The literal sequence: how does a BitV user
   go from "connected wallet" to "Cleanverse-verified" from Cleanverse's
   point of view?
6. **Terminology mapping** — Where Cleanverse's terms differ from BitV's
   product language, preserve Cleanverse's terms in the implementation
   (types, function names, comments) while keeping BitV's product
   terminology in UI-facing copy.

`services/cleanverse/types.ts` and `services/cleanverse/client.ts` should
only be filled in once this list is resolved with citations back to the
actual documentation.
