-- 011_create_catalog_enums.sql
-- Domain enumerations for the catalog & pricing capability.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("Enums").

CREATE TYPE public.product_type AS ENUM ('experience', 'accommodation', 'package');

CREATE TYPE public.product_status AS ENUM ('draft', 'active', 'inactive');

CREATE TYPE public.experience_difficulty AS ENUM ('easy', 'moderate', 'hard');

CREATE TYPE public.addon_unit AS ENUM ('per_person', 'per_unit', 'per_service');

CREATE TYPE public.charge_type AS ENUM ('per_person', 'per_night', 'per_group');
