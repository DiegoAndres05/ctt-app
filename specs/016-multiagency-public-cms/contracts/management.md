# Management contract

All management operations require an authenticated user and the user's agency
claim. The service must enforce the role in the backend.

| Operation | Administrator | Operator | Agent |
|---|---:|---:|---:|
| Create/update/activate/deactivate categories | Yes | Yes | No |
| Create/update/activate/deactivate lodging types and amenities | Yes | Yes | No |
| Create/update public profile | Yes | Yes | No |
| View/generate/regenerate/revoke public key | Yes | No | No |
| Configure migration source and complete CTT cutover | Yes | No | No |

## Key operations

### Generate or regenerate

Returns the clear-text key once, its creation time, and (for regeneration) the
previous key expiration time exactly seven days after rotation. The clear-text
secret must not be returned by later reads.

### Revoke

Invalidates the selected key immediately and records actor and time. Repeated
revocation is idempotent and does not reveal key material.

## Profile and taxonomy validation

- IDs/codes are agency-local and stable.
- Bilingual names are required and non-blank.
- A used value cannot be physically deleted.
- A deactivated value cannot be assigned to new or edited listings.
- Profile languages are `es`, `en`, or both.
- Profile currency must be supported by the platform.
- Public logo and social links are optional; omitted values are absent from the
  public projection rather than empty placeholders.

