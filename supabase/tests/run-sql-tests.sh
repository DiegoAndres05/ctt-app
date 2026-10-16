#!/usr/bin/env bash
# Applies every migration to a throwaway PostgreSQL 17 container shaped like a Supabase
# project, then runs the SQL test suites against it.
#
# The container is created and destroyed by this script, so the run is reproducible and never
# touches a real project. Requires Docker.
#
# Usage: supabase/tests/run-sql-tests.sh [test-file ...]
#        (no arguments runs every supabase/tests/*_test.sql)
#
# Catalog & pricing suites (002) and public listing suites (009) are picked up by the
# same glob once present, including:
#   catalog_rls_test.sql, pricing_rules_test.sql, price_freeze_test.sql,
#   package_composition_test.sql, catalog_security_review_test.sql,
#   catalog_performance_probe_test.sql,
#   public_listing_rules_test.sql, public_listing_rls_test.sql,
#   public_cutover_test.sql, public_sold_out_test.sql
# Customer request suites (003):
#   customer_intake_core_test.sql, customer_requests_rls_test.sql,
#   public_request_intake_test.sql, whatsapp_intake_test.sql,
#   request_workflow_test.sql, customer_privacy_test.sql
# Pre-reservation suites (004):
#   pre_reservation_core_test.sql, pre_reservation_rls_test.sql,
#   availability_verification_test.sql, pre_reservation_consolidation_test.sql,
#   verification_traceability_test.sql
# Quotation suites (005):
#   quotation_pricing_test.sql, quotation_rls_test.sql, quotation_issue_test.sql,
#   quotation_public_test.sql, quotation_version_test.sql
# Reservation suites (006):
#   reservation_confirm_test.sql, reservation_rls_test.sql,
#   reservation_lifecycle_test.sql, reservation_changes_test.sql,
#   service_orders_test.sql
# There is no explicit file list to maintain; adding a `*_test.sql` is enough.

set -euo pipefail

readonly CONTAINER=cttadmin-sqlcheck
readonly IMAGE=postgres:17-alpine
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly MIGRATIONS_DIR="$REPO_ROOT/supabase/migrations"
readonly TESTS_DIR="$REPO_ROOT/supabase/tests"

psql_file() {
  docker exec -i "$CONTAINER" psql \
    --username postgres --dbname postgres \
    --no-psqlrc --quiet --set ON_ERROR_STOP=1 < "$1"
}

cleanup() {
  docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
echo "==> starting $IMAGE as $CONTAINER"
docker run --detach --name "$CONTAINER" \
  --env POSTGRES_PASSWORD=postgres \
  "$IMAGE" >/dev/null

# The entrypoint accepts connections on a temporary local socket while it initialises the
# cluster, then restarts the server. Poll with a real query and require several consecutive
# successes so the restart cannot be mistaken for readiness.
ready=0
for _ in $(seq 1 120); do
  if docker exec "$CONTAINER" psql --username postgres --dbname postgres \
    --no-psqlrc --quiet --tuples-only --command 'SELECT 1' >/dev/null 2>&1; then
    ready=$((ready + 1))
    [ "$ready" -ge 3 ] && break
  else
    ready=0
  fi
  sleep 0.5
done

if [ "$ready" -lt 3 ]; then
  echo "postgres did not become ready" >&2
  exit 1
fi

echo "==> applying Supabase harness"
for fixture in "$TESTS_DIR"/harness/*.sql; do
  echo "    $(basename "$fixture")"
  psql_file "$fixture"
done

echo "==> applying migrations"
for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "    $(basename "$migration")"
  psql_file "$migration"
done

echo "==> applying seed"
psql_file "$REPO_ROOT/supabase/seed.sql"

if [ "$#" -gt 0 ]; then
  suites=("$@")
else
  suites=("$TESTS_DIR"/*_test.sql)
fi

for suite in "${suites[@]}"; do
  echo "==> running $(basename "$suite")"
  psql_file "$suite"
done

echo "==> all suites passed"
