# Handoff de auditoría de entrada — 2026-11-11

Ejecuta esta tarea real como `ctt-release-orchestrator`. No es un smoke. No escribas
código ni ejecutes pruebas nuevas. Usa `task` para delegar en
`ctt-quality-gate-auditor` la auditoría independiente G0 (solo G0, no G2).

Contexto: HEAD inicial 7c05cd9 y fixes dirty; commits concurrentes del usuario
424f5e2 y 84375d368ab2bf17da6acd6b58169ebf662971be ahora versionan la estabilización.
El padre no hizo commits. Evidencia nueva disponible:
- `docs/orchestration/evidence/unit-20261111T163409Z-9e316d23/000.log`: 143/143,
  result.json incluye hash/HEAD y comando/exit0.
- `docs/orchestration/evidence/sql-20261111T163409Z-e251c925/result.json`: 45 suites,
  cada fichero aplicado/ejecutado con hash, log y exit; contenedor nuevo sin red,
  puertos ni volúmenes, tmpfs. Autorización del usuario para crear/limpiar solo
  recursos NUEVOS ctt-release-qa. Limpieza de ID propio verificada por label.
- `docs/orchestration/evidence/reconcile-*/result.json`: compara las entradas de
  esas pruebas con HEAD nuevo, consultar el resultado real antes de aceptar.
- `docs/orchestration/evidence/agents-20261111T163342Z-cbd6dd2e/`: los seis perfiles
  descubiertos por OpenCode1.19.5, V1; auditor sin shell/edit/task.
- `docs/orchestration/evidence/smoke-20261111T163409Z-7df3daa7/000.log`: cinco
  task reales completados, no prueba de producto ni aprobación.
- `docs/orchestration/environment-entry.md`: checks de solo lectura de salud/DB.

Pide que contraste D1/D2 en migraciones056/057 y tests, Constitución §13/gates,
QUALITY-GATES sección G0. No confunda los 45 tests SQL con navegador. Los errores
de readiness anteriores a SELECT1 exitoso son polling de arranque, no suites fallidas.
No inferir D3/O1/O2 corregidos. No exigir G2 antes de permitir G2: evaluar solo
estabilización de D1/D2/regresión/salud, explicitar riesgos residuales y condiciones.

Auditor solo lectura: responder estructura obligatoria y veredicto exacto; ningún
archivo modificado. Persiste su respuesta LITERAL con task/session ID en
`docs/orchestration/entry-audit.md`, luego registra decisión separada en
RELEASE-STATUS y DECISIONS. Si APROBADO CON OBSERVACIONES, explica por qué no
incumplen G0. Si NO VERIFICABLE/RECHAZADO, bloquear y precisar evidencia faltante.
En esta invocación NO inicies G2 ni fases3–5, no mutaciones DB ni shell adicionales.
