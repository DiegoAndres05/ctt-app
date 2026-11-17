# Quickstart: Base multiagencia del contenido público

## Prerequisites

- Docker and the local Supabase test dependencies.
- Node.js and npm versions required by the repository.
- A clean local database initialized from all migrations.

## Automated validation

Run the focused SQL suites after adding the feature migrations:

```bash
./supabase/tests/run-sql-tests.sh \
  supabase/tests/public_cms_config_test.sql \
  supabase/tests/public_key_security_test.sql \
  supabase/tests/public_profile_test.sql \
  supabase/tests/public_source_transition_test.sql
```

Run the frontend checks:

```bash
npm test -- --watch=false
npm run lint
npm run build
```

## Required scenarios

1. Create two agencies and confirm each receives independent example categories,
   accommodation types, amenities and a public profile.
2. As Operator, create, rename, deactivate and list taxonomy values; as Agent,
   confirm every write is rejected.
3. Assign a type and amenity to a published listing, deactivate them, and confirm
   the published listing still displays its saved values.
4. As Administrator, generate a key, read the public projection, regenerate it,
   confirm the old key works for seven days, then confirm it is rejected after
   expiry. Revoke a key and confirm immediate rejection.
5. Compare responses for an unknown, revoked and expired key; they must have the
   same generic denial shape and must not reveal agency existence.
6. Confirm the public projection contains profile and published catalog data only,
   with no users, clients, notes, providers, costs or operational tariffs.
7. Verify CTT's eight category identifiers, listing slugs and image references are
   unchanged. During transition, the organization identifier remains accepted only
   for CTT; after transition it is rejected.
8. Mark one agency as migration-required and confirm cutover is blocked while a
   manifest item is missing. Mark another as migration-free and confirm direct
   publication is allowed.

See [data-model.md](./data-model.md) for entities and [contracts/](./contracts/)
for the public and management interface shapes.

