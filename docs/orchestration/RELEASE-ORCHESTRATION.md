# Plan maestro de release

Restauración: **2026-11-13**. Documento de procedimiento; no acredita gates aprobados.

## Arranque y línea base

Los seis agentes leen al iniciar/reanudar este documento, `AGENT-RESPONSIBILITIES.md`, `QUALITY-GATES.md` y `DECISIONS.md`; también `RELEASE-STATUS.md` e `initialization-report.md` cuando estén disponibles. Estos dos últimos pertenecen al padre. Su ausencia se informa, no se reconstruyen estados por conjetura.

Línea base comunicada: rama `main`, HEAD `2844c6fc7a361ee821d9b118abf4d34fdb4f7868`, estabilización integrada por `62bf01c` y corrección de lint `2844c6f`. Antes de ejecutar, comprobar SHA completo, diff y archivos sin seguimiento: los cambios concurrentes/preexistentes son trabajo ajeno hasta identificar su propietario. No limpiar ni sobrescribirlos.

Los resultados históricos de **143 pruebas unitarias y 45 SQL** corresponden a `84375d3`, del **2026-11-11**; no aprueban el candidato actual. El smoke previo completó **5 de 5**, pero tampoco sustituye G0. La última auditoría real de prerrequisitos mediante CLI falló con **429 por cuota, sin dictamen**. G0 sigue sin aprobación verificable: **no iniciar G2 antes de G0**.

## OpenCode persistente

Otro agente restaura las seis definiciones; el padre verifica su funcionamiento. Último descubrimiento: CLI **1.19.5**, configuración **V1**, `agent` singular y permisos efectivos `permission`/`bash`/`task`; Markdown en `.opencode/agents/` confirmado en el descubrimiento previo. La documentación web V2 difiere. La nueva comprobación de configuración/carga/runtime está pendiente.

No cambiar `default_agent` ni fijar modelo en las definiciones: heredar el modelo seleccionado y verificado. Reiniciar OpenCode tras la restauración. Invocaciones previstas desde este repositorio:

```sh
opencode --agent ctt-release-orchestrator
opencode run --agent ctt-release-orchestrator -m openai/gpt-6-astra 'Reanuda leyendo docs/orchestration/RELEASE-ORCHESTRATION.md y el estado persistido. Verifica G0 antes de iniciar G2 y respeta los locks y autorizaciones.'
```

El modelo del ejemplo figuraba en el listado del CLI; eso no prueba una invocación actual exitosa. `-m` selecciona el modelo solo para esa ejecución, no modifica el modelo por defecto. El padre registra la carga de los seis agentes, modelo efectivo, delegación y límites de permisos, sin presentar el smoke histórico como nueva evidencia.

## Secuencia y límites

| Gate/fase | Entrada | Entrega |
| --- | --- | --- |
| G0 — Prerrequisitos | Revisión actual, agentes/configuración restaurados, runtime y alcance comprobables; ver QUALITY-GATES.md | Auditoría independiente de prerrequisitos y decisión persistida. **No exige resultados de G2.** |
| G2 / fase 2 — Local | G0 habilitante, lock y operaciones locales autorizadas | Recorrido fresco de 18 pasos, suites y negativos; informe local y auditoría G2 |
| G3 / fase 3 — Integración | G2 habilitante; ruta Next.js, revisión y acceso aportados/autorizados | Integración real de contratos 003/009, pruebas de ambos repos e informe auditado |
| G4 / fase 4 — Staging | G3 habilitante; infraestructura y candidato identificados; operaciones autorizadas | Validación integrada, observabilidad y recuperación; informe auditado |
| G5A / fase 5A — Candidato | G4 habilitante; revisiones y artefactos identificados | Plan de producción y candidato auditado, sin efectos en producción |
| G5B / fase 5B — Producción | G5A habilitante y aprobación humana específica por operación | Operaciones autorizadas, validación posterior y auditoría de resultados |

**Durante esta restauración/inicialización no ejecutar fases 3, 4, 5A ni 5B.** Esta entrega restaura documentación; no ejecuta G2. Una aprobación de calidad no concede autorización operativa.

## Fase 2: recorrido nuevo desde cero

Tras G0, usar `run_id` nuevo, datos sintéticos, dos organizaciones y roles admin/operator/agent. El usuario autorizó en este hilo crear y desechar únicamente recursos Docker **nuevos** `ctt-release-qa...`. Verificar contexto Docker local, nombres exactos, redes, volúmenes y puertos sin colisión. No resetear Supabase existente, reciclar volúmenes ajenos ni copiar datos reales. Registrar creación y disposición como operaciones separadas dentro del alcance concedido.

| Paso | Acción y resultado verificable |
| --- | --- |
| 1 | Registrar revisión/estado de trabajo, versiones, identidad, destinos efectivos, G0 y autorizaciones vigentes. |
| 2 | Crear recursos nuevos aislados; aplicar migraciones desde cero y fixtures sintéticos; conservar salidas. |
| 3 | Iniciar panel/backend contra esos recursos; comprobar sesiones, roles y aislamiento entre organizaciones. |
| 4 | Crear catálogo operativo y tarifas: experiencia, alojamiento y complementos/paquete necesarios para el viaje. |
| 5 | Crear fichas sintéticas de oferta, alojamiento y yate con ES/EN, imágenes y campos obligatorios; comprobar publicación y secciones. |
| 6 | Consultar contratos públicos locales: solo publicado/activo, contenido vigente y precio de vitrina independiente de tarifa. Esto no acredita integración Next.js. |
| 7 | Capturar solicitud web por organización/ficha: cliente, canal Web, estado Recibida, bandeja actualizada y ninguna reserva creada. |
| 8 | Repetir envío y contactos conflictivos: idempotencia, prioridad email/teléfono, completar vacíos sin sobrescribir ni fusionar perfiles. |
| 9 | Capturar WhatsApp manual y simulado: anexado a solicitud abierta, deduplicación de mensajes y adaptador real inactivo sin credenciales. |
| 10 | Asignar/gestionar solicitud, notas e historial; registrar primera gestión y validar transiciones. |
| 11 | Convertir solicitud a pre-reserva con varias líneas, fechas y cantidades; comprobar vínculos y estado pendiente, sin confirmar reserva. |
| 12 | Verificar líneas como operador con contacto sintético, actor, tiempos y vigencia; comprobar consolidación y casos separados no disponibles/expirados. |
| 13 | Crear cotización elegible: cálculo servidor, desglose, descuentos autorizados, moneda, términos y vigencia limitada por proveedor. |
| 14 | Emitir cotización: referencia/versionado, snapshot económico, vista móvil y resumen WhatsApp; cambios de tarifa/vitrina no alteran lo emitido. |
| 15 | Versionar y aceptar versión vigente; probar por separado rechazo, expiración, anulación y tokens inválidos sin perder historia. |
| 16 | Registrar depósito/comprobante sintético y confirmar desde cotización aceptada vigente; verificar localizador, pasajeros, importes y voucher. |
| 17 | Generar órdenes por proveedor sin precios finales ni datos de terceros; recorrer ejecución/completada y casos separados de cancelación/modificación/contingencia auditados. |
| 18 | Conciliar embudo, tiempos, ranking, finanzas, CSV y auditoría; cerrar negativos, RBAC/RLS, redacción, consola/red y suites; entregar informe para auditoría G2. |

Aplicar la matriz transversal de QUALITY-GATES.md durante el recorrido. Cada fallo conserva evidencia; las correcciones necesitan lock, nueva identificación del candidato, repetición completa desde cero y regresión pertinente. Desechar solo los recursos nuevos inventariados y autorizados tras capturar evidencia; informar remanentes, sin limpieza global.

## Fases posteriores: trabajo previsto, no autorizado en inicialización

**Fase 3:** la ruta Next.js sigue desconocida. Pedir ubicación autorizada y revisión; no buscar fuera del workspace, clonar ni explorar sitios externos por inferencia. Tras habilitarla, identificar ambos repositorios, bloquear rutas y conectar consumidor/contratos 003/009 en entorno de prueba. Validar idiomas, imágenes, secciones, publicación/despublicación, agotados, revalidación/caché, solicitudes, idempotencia, CORS, errores, aislamiento y ausencia de credenciales privilegiadas en cliente/bundles. Probar ambos extremos y consola/red. Ensayar continuidad de catálogo/slugs/precios con fixtures; no confundirlo con inventario real aprobado.

**Fase 4:** infraestructura desconocida. Solicitar cuentas/proyectos/dominios y procedimientos autorizados. Verificar identidad efectiva y destino antes de cualquier operación; no asumir que una URL configurada es staging. Desplegar solo candidato autorizado; comprobar configuración, secretos por referencia, TLS/CORS, migraciones/Storage, recorrido integrado, negativos, regresión, rendimiento de specs, logging, monitorización y recuperación. Despliegue, migración y recuperación requieren aprobaciones separadas. Registrar lo realmente desplegado; rollback de aplicación no implica rollback de datos.

**Fase 5A:** congelar revisiones y hashes de artefactos, migraciones, compatibilidad, configuración sin secretos, aceptación de negocio, riesgos/responsables, ventana propuesta, checks previos/posteriores, condiciones de aborto y recuperación. Documentar respaldo/restauración y evidencia del ensayo staging. Para 009, planificar inventario real, continuidad de URLs/imágenes/precios y cambio de fuente: si falta alguna ficha vigente, bloquear el cambio. Acceso/copia real requieren permiso separado; fixtures no demuestran completitud real. Entregar candidato y plan sin producción.

**Fase 5B:** exigir aprobación inequívoca de cada operación. Revalidar destino/identidad/revisión/ventana/alcance/respaldo; ejecutar una vez, registrar efectos y comprobar resultado. Detenerse ante desviaciones. Reintento, siguiente paso y recuperación necesitan autorizaciones propias. «Continúa», aprobar un gate o aprobar un plan no autorizan producción. Cerrar con validación posterior autorizada, monitorización y auditoría independiente.

## Autorización de operación única

No hay commits, push, deploy, reset ni copia de datos reales automáticos. Registrar antes de cada operación sujeta a autorización:

```text
ID / AGENTE / FASE / RUN_ID:
FECHA/HORA CON ZONA:
APROBADOR Y REFERENCIA AL MENSAJE EXPLÍCITO:
OPERACIÓN ÚNICA / COMANDO EXACTO / DIRECTORIO:
DESTINO (entorno, host/proyecto/cuenta, recursos exactos):
IDENTIDAD/CREDENCIAL EFECTIVA (referencia sin secreto):
REPOSITORIO / REVISIÓN / HASH DEL ESTADO DE TRABAJO:
VENTANA (inicio y fin):
ALCANCE MÁXIMO (rutas, recursos, datos y efectos):
PRECONDICIONES / RESULTADO ESPERADO / ABORTO:
ESTADO (pendiente/concedida/consumida/vencida/revocada):
CONSUMO (fecha/hora, salida, resultado y evidencia):
```

La autorización Docker actual cubre solo los recursos nuevos indicados: vincular el mensaje del usuario y los nombres exactos, sin inventar vigencia ni ampliar alcance. Si falta precisión necesaria, solicitarla. Una plantilla vacía no autoriza nada; una aprobación consumida no se reutiliza.

Permisos de herramienta **solo una vez**, nunca `--auto`. Los permisos OpenCode **no son un sandbox**: shell, scripts, procesos hijos, MCP y credenciales heredadas pueden alcanzar otros destinos. Inspeccionar contexto Docker, enlaces Supabase, remotos, variables de destino e identidad efectiva sin imprimir secretos. Una regla `allow` no reemplaza autorización humana; destino/credencial no verificable bloquea la operación.

## Entregas y reanudación

- Evidencia nueva: `docs/orchestration/evidence/<run_id>/<fase>/`, con manifiesto, revisión, fechas reales, comandos, resultados y referencias a requisitos; redactar secretos/PII antes de persistir.
- Local: `docs/qa/reports/local-e2e-report.md`.
- Integración: `docs/integration/integration-report.md`.
- Staging: `docs/release/staging-validation-report.md`.
- Producción: `docs/release/production-release-plan.md` y evidencia de operaciones.

Al reanudar, comprobar estado, revisiones, destinos, locks, aprobaciones consumidas/vencidas y primer gate no habilitante. No inferir éxito ni reintentar mutaciones de un informe incompleto. El auditor devuelve texto; el padre lo persiste literalmente con metadatos separados.
