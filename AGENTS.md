# CTTAdmin

Angular 22 + Supabase admin panel for tourism-agency operations.

Identity & Access (auth, multi-tenant RLS, RBAC, audit, agency onboarding):
see `docs/modules/identity-access.md`.

Catalog & Pricing (experiences, accommodations, packages, add-ons, tariffs):
see `docs/modules/catalog-pricing.md`.

Customers & Requests (customer profiles, multichannel requests, WhatsApp intake boundary):
see `docs/modules/customer-requests.md`.

Pre-Reservations & Availability (pre-reservations, human availability verification queue,
quote eligibility): see `docs/modules/pre-reservations.md`.

Quotations (commercial proposals, server-side pricing, public token): see docs/modules/quotations.md.

Reservations (confirmed trips, manual deposit, service orders): see docs/modules/reservations.md.

Analytics (funnel, ops times, product ranking, CSV): see `docs/modules/analytics.md`.

Blog (multi-agency articles, public read, WordPress migration): see `docs/modules/catalog-pricing.md`
(«Blog (013)») and `docs/adr/0004-blog-authoring-in-panel.md`.

Blog translation (self-hosted LibreTranslate, Edge Function `translate-blog`, character quota):
see `docs/modules/catalog-pricing.md` («Traducción del blog (017)») and
`docs/adr/0005-self-hosted-machine-translation.md`.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at specs/017-blog-translation/plan.md
<!-- SPECKIT END -->
