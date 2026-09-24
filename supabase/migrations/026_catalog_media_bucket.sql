-- 026_catalog_media_bucket.sql
-- Public catalog media bucket + policies for operator/admin writes by org prefix.
-- Harness has no storage schema; create minimal stubs so this migration applies in
-- SQL tests. On real Supabase, storage.buckets / storage.objects already exist.

CREATE SCHEMA IF NOT EXISTS storage;

DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    CREATE TABLE storage.buckets (
      id text PRIMARY KEY,
      name text NOT NULL,
      public boolean NOT NULL DEFAULT false,
      file_size_limit bigint,
      allowed_mime_types text[],
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  END IF;

  IF to_regclass('storage.objects') IS NULL THEN
    CREATE TABLE storage.objects (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      bucket_id text NOT NULL REFERENCES storage.buckets (id) ON DELETE CASCADE,
      name text NOT NULL,
      owner uuid,
      metadata jsonb DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (bucket_id, name)
    );
  END IF;
END;
$$;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'catalog-media',
  'catalog-media',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  updated_at = now();

-- Policies: use split_part for org prefix so harness and Supabase both work
-- without depending on storage.foldername().
DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN others THEN
    NULL;
END;
$$;

DROP POLICY IF EXISTS catalog_media_public_read ON storage.objects;
DROP POLICY IF EXISTS catalog_media_operator_insert ON storage.objects;
DROP POLICY IF EXISTS catalog_media_operator_update ON storage.objects;
DROP POLICY IF EXISTS catalog_media_operator_delete ON storage.objects;

CREATE POLICY catalog_media_public_read ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'catalog-media');

CREATE POLICY catalog_media_operator_insert ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'catalog-media'
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  );

CREATE POLICY catalog_media_operator_update ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'catalog-media'
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  )
  WITH CHECK (
    bucket_id = 'catalog-media'
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  );

CREATE POLICY catalog_media_operator_delete ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'catalog-media'
    AND (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND split_part(name, '/', 1) = (auth.jwt() ->> 'organization_id')
  );
