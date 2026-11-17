# Data Model: Base multiagencia del contenido público

## Existing entities extended

### `public.public_sites`

Represents the public-source configuration for one agency.

- `organization_id`: owner agency and tenant boundary.
- `source`: `legacy` or `panel`.
- `cutover_completed_at`, `cutover_completed_by`: immutable evidence of completed
  source transition.
- New transition controls must identify whether the organization is migrating from
  an existing external site; agencies without an external source bypass the manifest
  gate.

### `public.public_categories`

Agency-owned public category.

- Existing identity `(organization_id, id)` remains unchanged.
- `id`: stable lowercase identifier.
- `name_es`, `name_en`: required bilingual labels.
- `is_active`: assignment availability.
- `protected`: preserves CTT's existing eight categories from deletion or renaming
  where required for URL/filter compatibility.

### `public.public_listings`

Existing published listing. This feature must not change its `id`, `public_slug`,
cover references, gallery references, or published content semantics.

- `organization_id`: tenant boundary.
- `public_category_id`: agency-owned category.
- `lodging`: existing structured lodging payload; its type and amenities become
  references to agency configuration values while retaining a display snapshot for
  already-published content.

## New entities

### `public.public_taxonomy_values`

Configurable agency-owned values for accommodation types and amenities.

- `id`: UUID.
- `organization_id`: owning agency.
- `kind`: `lodging_type` or `amenity`.
- `code`: stable agency-local identifier.
- `name_es`, `name_en`: required bilingual labels.
- `is_active`: available for new or edited listings.
- `protected`: optional protection for seeded compatibility values.
- `created_at`, `updated_at`: lifecycle timestamps.
- Unique key: `(organization_id, kind, code)`.

Deletion rules:

- A value referenced by a published listing cannot be physically deleted.
- It can be deactivated; existing published snapshots keep displaying it until the
  listing is edited.
- A value not referenced by any listing may be deleted or deactivated according to
  the management operation contract.

### `public.public_profiles`

One public-facing profile per agency.

- `organization_id`: primary key and tenant boundary.
- `commercial_name`: required public name.
- `logo_ref`: optional public logo reference.
- `primary_color`: validated public color value.
- `contact_email`, `contact_phone`, `whatsapp`: optional public contact channels.
- `social_links`: structured map of supported social networks and URLs.
- `languages`: one or both of `es`, `en`.
- `currency`: supported three-letter public currency.
- `created_at`, `updated_at`: lifecycle timestamps.

### `public.public_access_keys`

Rotatable public credentials for one agency.

- `id`: UUID.
- `organization_id`: owning agency.
- `key_fingerprint`: unique non-reversible fingerprint.
- `created_at`: creation time.
- `expires_at`: nullable for current key; populated for a rotated predecessor.
- `revoked_at`: immediate invalidation marker.
- `created_by`, `revoked_by`: actor references where applicable.
- `last_used_at`: optional operational signal; must not expose the secret.

At most one current key and one or more historical records may be valid during
their seven-day grace periods. The clear-text key is returned only at creation or
regeneration time and is never stored.

### `public.public_source_config`

Agency-level source transition policy.

- `organization_id`: primary key and tenant boundary.
- `migration_required`: whether an external existing site must be copied before
  cutover.
- `organization_identifier_until`: transition end for the CTT compatibility path.
- `created_at`, `updated_at`: lifecycle timestamps.

For agencies without migration, `migration_required = false` and publication is not
blocked by `public_cutover_items`.

### Audit records

Use the existing audit model for taxonomy, profile, key, and source-policy actions.
Each event must include actor, organization, action, timestamp, and a safe metadata
summary. Key material must never appear in audit metadata.

## Relationships and invariants

- Every new entity belongs to exactly one `organization_id`.
- A user may manage only the organization in the authenticated claims.
- Operator and Administrator manage taxonomy and profile; only Administrator manages
  access keys and source-transition policy.
- Public consumers can access only the published projection of one agency.
- Invalid, revoked, expired, or unknown keys resolve to the same generic denial.
- CTT's existing category IDs, listing slugs, image references, and published rows
  remain stable.

## State transitions

### Public access key

`current` → `grace_period` (regeneration) → `expired`

`current` → `revoked` (explicit revocation)

The grace period lasts seven days. A revoked key does not remain valid during grace.

### Public source

`legacy` → `panel` only when:

- `migration_required = false`, or
- every required manifest item has a published active listing.

The transition is one-way for the current release and preserves existing public
identifiers and images.

