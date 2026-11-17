# Public consumer contract

## Authentication

The consumer supplies one public access key. The key authorizes only the public
projection and traveler-request intake for the associated agency.

Invalid, unknown, revoked and expired keys use the same generic denial response:

```json
{
  "error": "PUBLIC_ACCESS_UNAVAILABLE"
}
```

The response must not identify the agency or disclose whether the key existed.

## Read public agency

`GET /public/site`

Response:

```json
{
  "profile": {
    "commercialName": "Agencia Demo",
    "logo": "public/logo.svg",
    "primaryColor": "#0F766E",
    "contactEmail": "contacto@example.test",
    "contactPhone": "+57 300 000 0000",
    "whatsapp": "+57 300 000 0000",
    "socialLinks": {
      "instagram": "https://instagram.com/example"
    },
    "languages": ["es", "en"],
    "currency": "COP"
  },
  "catalog": {
    "categories": [],
    "offers": [],
    "lodgings": [],
    "yachts": []
  }
}
```

Only active, published listings for the authenticated public key's agency are
returned. Internal users, customers, notes, providers, costs and operational
tariffs are excluded.

## Submit traveler request

`POST /public/trip-requests`

Request:

```json
{
  "listingSlug": "islas-capri-premium",
  "placement": "catalog",
  "traveler": {
    "fullName": "Nombre del viajero",
    "email": "traveler@example.test",
    "phone": "+57 300 000 0000"
  },
  "message": "Quiero información para cuatro personas."
}
```

Response:

```json
{
  "requestId": "opaque-request-id",
  "status": "received"
}
```

The request is associated with the agency identified by the key. It is not a
reservation confirmation.

## CTT compatibility

During the configured transition window, CTT may use its organization identifier
as an alternate consumer credential. This exception is not available to other
agencies. After the transition end, only the public key is accepted.

