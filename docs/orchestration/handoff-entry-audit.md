# Auditoría real G0 y primera delegación condicionada

Fecha 2026-11-13. Actúa como orquestador usando tus agentes persistentes reales.
La auditoría anterior del11nov falló por429; han pasado dos días y esta nueva
ejecución tiene evidencia/revisión distintas. No repitas suites ni ejecutes shell.

Delega INMEDIATAMENTE a ctt-quality-gate-auditor la auditoría G0, con este contexto
y rutas (evita releer y copiar todos los logs tú antes de delegar):

- Repo actual main2844c6fc7a361ee821d9b118abf4d34fdb4f7868; fixes056/057 integrados.
- Nuevas unitarias: docs/orchestration/evidence/unit-20261113T160606Z-2ccbb6dc/
  result.json, input-hashes.json, 000.txt.
- Nuevas SQL: docs/orchestration/evidence/sql-20261113T160606Z-f0844aec/
  result.json, input-hashes.json y logs referenciados.45 suites completas, fallos
  readiness al arrancar no son tests fallidos. Contenedor nuevo autorizado
  ctt-release-qa, network none/tmpfs, eliminado solo ID propio comprobado por label.
- Configs reales restauradas y descubiertas:
  docs/orchestration/evidence/agents-20261113T160606Z-2aa54024/.
- Salud local13nov16:07UTC: app4200 HTTP200, auth/v1/health54321 HTTP200;
  docker ps muestra DB/auth/rest/kong saludables; SELECT version ...schema_migrations
  devuelve057,056,055,054. Son observaciones nuevas del instalador, NO E2E ni
  identidad del bundle, y no sustituyen evidencia del stack aislado futuro.

Auditor debe leer Constitución§13/gates11–15, QUALITY-GATES secciónG0, cambios056/
057 y regresiones específicas. Solo lectura, sin shell/modificaciones/delegación.
Evaluar D1/D2/regresiones/salud de entrada; G0 no requiere resultadoG2 (no circular).
No declarar D3/O1/O2 cerrados ni usar histórico como prueba actual.
Retornar dictamen estructurado y cada observación con evidencia/impacto/cierre.

Persiste respuesta LITERAL en docs/orchestration/entry-audit.md con taskID; tu
decisión separada en RELEASE-STATUS y DECISIONS. Si no verificable/rechazado: detener.

SI G0 habilita fase2, delega a ctt-local-e2e primera tarea real de fase2: inspección
de contratos/entorno necesario y preparación del plan ejecutable desde cero.
Debe crear docs/qa/reports/local-e2e-report.md con18 pasos y estado real por paso;
no declarar pasos ejecutados. Puede crear un runner bajo docs/qa/ para revisión.
Alcance de esta invocación: SOLO lectura y escritura del informe/preparación; NO
shell ni mutaciones DB (el instalador revisará los comandos/scripts antes de
ejecutarlos con aprobación de recursos nuevos). Identificar exactamente recursos,
scripts, navegador/dependencias y bloqueos. No usar Supabase existente para fixtures.
No fase3/4/5 ni acceso externo. No commits/push. Los permisos no se autoaprueban.
Concluye con taskIDs reales, G0 y siguiente operación exacta necesaria para G2.
