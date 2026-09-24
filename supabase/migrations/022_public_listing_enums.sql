-- 022_public_listing_enums.sql
-- Public listing / site CMS enums and audit event types for feature 009.
-- Source of truth: specs/009-catalog-site-cms/data-model.md

CREATE TYPE public.public_placement AS ENUM ('catalog', 'lodging', 'yacht');

CREATE TYPE public.public_listing_status AS ENUM ('draft', 'published', 'unpublished');

CREATE TYPE public.public_source AS ENUM ('legacy', 'panel');

CREATE TYPE public.public_image_role AS ENUM ('cover', 'gallery');

CREATE TYPE public.lodging_type AS ENUM ('casa', 'apartamento', 'finca', 'habitacion');

CREATE TYPE public.yacht_icon AS ENUM (
  'people', 'bed', 'shower', 'droplet', 'armchair', 'boat', 'kitchen',
  'star', 'snow', 'users', 'sun', 'music', 'map'
);

CREATE TYPE public.lodging_amenity AS ENUM (
  'wifi', 'pool', 'ac', 'kitchen', 'parking', 'terrace', 'washer', 'tv', 'bbq'
);

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_listing_published';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_listing_unpublished';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_image_replaced';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_listing_sold_out_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'public_cutover_completed';
