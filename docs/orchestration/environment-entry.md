# Entorno de entrada — observaciones nuevas 2026-11-11

Comprobaciones realizadas por el agente instalador, solo lectura:

| Comando | Resultado |
|---|---|
| `docker context show` | `desktop-linux` |
| `docker context inspect --format '{{.Endpoints.docker.Host}}'` | socket Unix local bajo `~/.docker/run/docker.sock` |
| `docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'` | 11 contenedores CTT/Supabase; DB/auth/storage/gateway saludables |
| `docker exec supabase_db_cttadmin psql -U postgres -d postgres -Atc 'SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 4;'` | `057`, `056`, `055`, `054`; exit0 |
| `curl --max-time 10 -fsS -o /dev/null -w 'App HTTP %{http_code}\n' http://127.0.0.1:4200/` | HTTP200, exit0 |
| `curl --max-time 10 -s -o /dev/null -w 'Supabase gateway HTTP %{http_code}\n' http://127.0.0.1:54321/auth/v1/health` | HTTP200, exit0 |

Son verificaciones de operatividad, no prueban identidad del bundle Docker con el
working tree actual ni el flujo comercial. El stack existente no se usará como
base desechable. El registro de migraciones no reemplaza comparar definiciones;
las regresiones nuevas se ejecutan aplicando todos los SQL efectivos desde cero.

Versiones ejecutadas: OpenCode1.19.5, Node24.18.0, npm11.16.0, Supabase CLI2.117.0.
Dependencias declaradas: Angular22.1, TypeScript6.0, Vitest4; PostgreSQL17 en pruebas.
No se han leído credenciales remotas ni invocado infraestructura remota del producto.
