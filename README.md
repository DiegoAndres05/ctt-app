# CTT Admin - Testing Branch Guide

This repository contains the `001-auth-tenant-access` implementation:

- Angular 22 standalone frontend with Signals and Signal Forms
- Supabase/PostgreSQL schema, RLS, auth hooks, and audit controls
- SQL and unit test suites for auth, RBAC, multi-tenant isolation, and onboarding

## Requirements

- Node.js `>=20.19.0`
- npm `>=11`
- Docker (for SQL validation tests)

## Quick Start

```bash
npm install
npm run build
npm run lint
npm run format:check
npm test
```

## Run Frontend

Set `src/environments/environment.development.ts` values:

- `supabaseUrl`
- `supabaseAnonKey`

Then run:

```bash
npm start
```

Open `http://localhost:4200`.

## Run SQL Validation Suite

This launches a disposable Postgres 17 container and validates migrations + security behavior.

```bash
./supabase/tests/run-sql-tests.sh
```

It covers:

- auth functions and lockout behavior
- RLS cross-tenant isolation
- audit immutability enforcement
- user management RPCs
- agency registration RPC
- performance probes

## Supabase Hooks Required (real environment)

In Supabase Dashboard:

1. Authentication -> Hooks -> **Customize Access Token (JWT) Claims** -> `custom_access_token_hook`
2. Authentication -> Hooks -> **Password Verification Attempt** -> `password_verification_hook`

Without these hooks, key auth and lockout behavior will not match this implementation.

## Key Documentation

- Feature spec: `specs/001-auth-tenant-access/spec.md`
- Plan: `specs/001-auth-tenant-access/plan.md`
- Tasks: `specs/001-auth-tenant-access/tasks.md`
- Validation evidence: `specs/001-auth-tenant-access/validation-evidence.md`
- ADRs: `docs/adr/`
