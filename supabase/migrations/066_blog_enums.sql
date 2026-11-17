-- 066_blog_enums.sql
-- Enums and audit event types for the multi-agency blog (feature 013).
-- Kept in its own migration: a new enum value cannot be used in the transaction that adds it.
-- Source of truth: specs/013-editorial-content/data-model.md

CREATE TYPE public.blog_article_status AS ENUM ('draft', 'published', 'retired');

COMMENT ON TYPE public.blog_article_status IS
  'draft: never published. published: visible on the agency site. retired: hidden, kept in the panel.';

CREATE TYPE public.blog_content_kind AS ENUM ('published', 'working');

COMMENT ON TYPE public.blog_content_kind IS
  'published: what the public read returns. working: draft or pending revision (never public).';

ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_article_published';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_article_changes_published';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_article_retired';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_article_deleted';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_source_changed';
ALTER TYPE audit.audit_event_type ADD VALUE IF NOT EXISTS 'blog_cutover_manifest_changed';
