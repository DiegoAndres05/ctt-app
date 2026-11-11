# Plan maestro de orquestación de release

Fecha de establecimiento: **2026-11-11**. Este documento define el procedimiento; no certifica ejecuciones ni gates aprobados.

## 1. Autoridad, arranque y situación inicial

Los seis agentes persistentes deben leer al iniciar y al reanudar:

1. Este documento.
2. [AGENT-RESPONSIBILITIES.md](AGENT-RESPONSIBILITIES.md).
3. [QUALITY-GATES.md](QUALITY-GATES.md).
4. [DECISIONS.md](DECISIONS.md).
5. `docs/orchestration/RELEASE-STATUS.md` e `initialization-report.md`, cuando el agente padre los haya creado. Su ausencia se registra; no se inventa su contenido.

Prevalecen `.specify/memory/constitution.md`, especialmente §13 y §15, y las especificaciones aplicables. Las decisiones de orquestación no cambian reglas de negocio. Conflictos o criterios ambiguos se elevan al responsable antes de aprobar el gate afectado.

La línea base **comunicada por el padre**, pendiente de volver a comprobar al ejecutar, es `main`, HEAD `7c05cd9...`, once archivos modificados y fixes `056`/`057` sin seguimiento. Los tests están pendientes de repetición. El prefijo no sustituye el SHA completo: registrar HEAD completo, diff y archivos sin seguimiento antes de ejecutar. Todo cambio preexistente se trata como trabajo del usuario; no limpiar, revertir, incorporar a commits ni atribuirlo al agente.

La inicialización instala/configura agentes y verifica su runtime por cuenta del padre. **No ejecuta las fases 3, 4, 5A ni 5B.** Tampoco la existencia de estos documentos prueba que los agentes hayan sido cargados o invocados. La fase 2 necesita su propia ejecución fresca y sus prerrequisitos.

### Configuración OpenCode descubierta

Según el descubrimiento comunicado por el padre, el CLI instalado es **1.19.5**, con configuración **V1** activa: `debug config` presenta `agent` en singular y permisos efectivos de `permission`, `bash` y `task`. El formato Markdown V1 en `.opencode/agents/` fue confirmado mediante la skill de configuración. La documentación web actual V2 describe otro esquema: no trasladarlo sin validarlo contra el CLI instalado.

El padre crea las seis definiciones persistentes y comprueba carga, delegación y permisos efectivos. No cambiar `default_agent` ni fijar `model` en las definiciones; deben heredar el modelo seleccionado y verificado. Reiniciar OpenCode después de los cambios de configuración y antes de comprobar su carga.

Invocación prevista desde el repositorio:

```sh
opencode --agent ctt-release-orchestrator
opencode run --agent ctt-release-orchestrator -m openai/gpt-6-astra 'Reanuda la orquestación leyendo docs/orchestration/RELEASE-ORCHESTRATION.md y el estado persistido; respeta los gates y las autorizaciones vigentes.'
```

`openai/gpt-6-astra` figura en los modelos listados por el CLI instalado según el descubrimiento recibido. **Eso no demuestra todavía que esta invocación se haya ejecutado correctamente.** El `-m` del ejemplo es una selección explícita para esa ejecución, no una configuración fija de los agentes. El padre debe conservar evidencia real de arranque, modelo efectivo y delegación; hasta entonces, runtime no verificado.

## 2. Secuencia maestra

| Fase | Responsable | Entrada obligatoria | Entrega y decisión |
| --- | --- | --- | --- |
| 2 — Local desde cero | `ctt-local-e2e` | Runtime verificado, línea base identificada, lock y recursos locales autorizados | Flujo nuevo de 18 pasos, suites, negativos, informe local y auditoría G2 |
| 3 — Integración Next.js | `ctt-integration-engineer` | G2 habilitante, ruta del repositorio y revisión aportadas por usuario, alcance y destinos autorizados | Integración real del consumidor con contratos 003/009, informe y auditoría G3 |
| 4 — Staging | `ctt-staging-validator` | G3 habilitante, infraestructura identificada, candidato reproducible y operaciones autorizadas | Validación del candidato en staging, informe y auditoría G4 |
| 5A — Candidato | `ctt-release-engineer` | G4 habilitante, revisiones y artefactos congelados | Plan de producción, manifiesto de candidato, recuperación y auditoría G5A; **sin producción** |
| 5B — Producción autorizada | `ctt-release-engineer` | G5A habilitante, aceptación humana y aprobaciones específicas vigentes | Una operación autorizada cada vez, validación posterior y auditoría G5B |

Cada cierre requiere auditoría independiente de `ctt-quality-gate-auditor`. El orquestador registra la decisión aplicando [QUALITY-GATES.md](QUALITY-GATES.md); el ejecutor no se autoaprueba. Una aprobación de calidad nunca es autorización operativa.

## 3. Fase 2: flujo local nuevo de 18 pasos

Ejecutar desde un entorno y conjunto de datos sintéticos nuevos, identificados por `run_id`. No reutilizar un recorrido histórico como evidencia nueva. El usuario aprobó en esta sesión crear y desechar recursos Docker locales **nuevos**, con nombres `ctt-release-qa...`; inventariar nombres exactos, volúmenes, redes, puertos y propietario antes de operar. Esa aprobación no permite resetear Supabase existente, reciclar sus volúmenes ni borrar recursos ajenos. Registrar cada operación concreta según §7.

Crear dos organizaciones sintéticas y cuentas de roles admin, operator y agent para las comprobaciones de aislamiento. No contactar proveedores reales: representar la verificación humana con datos sintéticos y actor identificado. Los pasos son un recorrido de negocio, no una lista de comandos que autorice efectos laterales.

| Paso | Acción fresca y resultado que se debe comprobar |
| --- | --- |
| 1 | Capturar SHA completo, estado de trabajo, versiones, identidad de ejecución, destinos efectivos y autorizaciones; identificar qué revisión exacta se prueba. |
| 2 | Crear recursos locales aislados `ctt-release-qa...`, aplicar desde cero las migraciones aplicables y cargar solo fixtures sintéticos; conservar resultados y manifestar su alcance. |
| 3 | Iniciar backend y panel contra esos recursos; comprobar login/logout, sesión, roles y aislamiento entre las dos organizaciones. |
| 4 | Crear catálogo operativo mínimo: experiencia, alojamiento, complementos/paquete necesarios y tarifas vigentes coherentes con las fechas del viaje. |
| 5 | Crear fichas públicas sintéticas de oferta, alojamiento y yate con ES/EN, categorías, imágenes y precios según 009; comprobar borrador, publicación y separación de secciones mediante contratos locales. |
| 6 | Consultar lectura pública sin sesión: solo publicado/activo, idioma e imagen vigentes; verificar que el precio de vitrina no cambia tarifas. El consumidor local del contrato no sustituye la integración Next.js de fase 3. |
| 7 | Enviar una solicitud web al endpoint público local por organización y ficha; comprobar cliente vinculado, canal Web, estado Recibida, ausencia de reserva y recepción en bandeja. |
| 8 | Repetir envío y casos de contacto en conflicto; comprobar idempotencia, prioridad email/teléfono y ausencia de sobrescritura/fusión de perfiles. |
| 9 | Registrar captura asistida y simulación local WhatsApp; verificar anexado a solicitud abierta, deduplicación de mensaje y adaptador real inactivo sin credenciales. |
| 10 | Asignar y gestionar la solicitud, añadir nota y consultar perfil/historial; registrar primera gestión y comprobar transiciones válidas. |
| 11 | Convertir la solicitud a pre-reserva con varias líneas, fechas y cantidades; comprobar vínculo, estado pendiente y que no existe reserva confirmada. |
| 12 | Como operador, gestionar cola y verificar cada línea con contacto sintético, actor, inicio/fin y límite de disponibilidad; comprobar consolidación, no disponibilidad y expiración en casos separados. |
| 13 | Crear cotización desde la pre-reserva elegible; comprobar cálculo autoritativo del servidor, descuentos autorizados, moneda, desglose, vigencia y términos. |
| 14 | Emitir cotización y comprobar consecutivo, snapshot económico, vista pública móvil y resumen WhatsApp; cambiar vitrina/tarifa de prueba y verificar que lo emitido no cambia. |
| 15 | Probar versionado y registrar aceptación de la versión vigente; usar casos separados para rechazo, expiración, anulación y tokens inválidos, preservando la historia. |
| 16 | Registrar depósito/comprobante sintético y confirmar reserva desde cotización aceptada vigente; comprobar unicidad, pasajeros, importes, trazabilidad y voucher. |
| 17 | Emitir órdenes por proveedor sin precios finales ni datos de otros proveedores; recorrer ejecución/completada y casos separados de cancelación, modificación y contingencia con auditoría. |
| 18 | Conciliar embudo, tiempos, ranking, finanzas, CSV y visor de auditoría con los datos creados; cerrar matriz de negativos, RBAC, redacción, consola/red, suites y evidencias; entregar informe y solicitar auditoría independiente. |

La matriz de negativos de QUALITY-GATES.md es obligatoria y se ejecuta durante el recorrido, no se reemplaza por capturas del camino feliz. Si un defecto requiere cambios, solicitar lock de corrección, registrar nueva revisión y repetir desde cero el flujo completo sobre el candidato corregido, además de la regresión pertinente. Conservar la ejecución fallida.

Después de capturar evidencia, desechar únicamente recursos nuevos inventariados y autorizados de esa ejecución. Informar recursos remanentes y resultado de limpieza; un fallo no justifica una limpieza global. El informe es `docs/qa/reports/local-e2e-report.md`, con evidencia en `docs/orchestration/evidence/`.

## 4. Fase 3: integración con sitio Next.js

**Bloqueo conocido:** no se conoce la ubicación del repositorio Next.js. Solicitar al usuario ruta autorizada, revisión/branch, instrucciones locales y alcance de edición. No buscar otros repositorios fuera del workspace, clonar remotos, recorrer directorios externos ni explorar el sitio real por inferencia. La URL presente en 009 no concede autoridad de búsqueda o extracción.

Tras habilitar la fase en otra ejecución:

- Identificar ambos repositorios y bloquear rutas de contratos y del consumidor antes de modificarlas.
- Conectar lectura pública y captura 003/009 a un backend de prueba autorizado; comprobar organización, ES/EN, imágenes, categorías, ofertas/alojamientos/yates y estados públicos.
- Validar caché/revalidación: despublicación, inactivación, agotado y nueva imagen reflejados en la siguiente consulta según 009. No conservar fallback que exponga contenido retirado.
- Comprobar solicitud, idempotencia, errores, CORS y aislamiento; no colocar credenciales privilegiadas en el cliente ni en bundles.
- Ensayar con datos sintéticos la matriz de migración del catálogo y continuidad de slugs/precios. La copia real y el cambio de fuente requieren aprobaciones separadas; el ensayo no acredita completitud del catálogo real.
- Ejecutar pruebas de ambos lados y revisión de consola/red, adjuntando revisiones exactas. Entregar `docs/integration/integration-report.md` y someter G3 al auditor.

## 5. Fase 4: staging

**Bloqueo conocido:** infraestructura, cuentas, proyectos, dominios, credenciales y procedimientos de staging desconocidos. No asumir que un destino configurado es staging.

Tras identificarlos y autorizar las operaciones, verificar identidad efectiva, clasificación del entorno, configuración, secretos referenciados sin valores, TLS/CORS, migraciones, Storage y aislamiento. Desplegar solo el candidato autorizado; repetir recorrido integrado y negativos con datos sintéticos, pruebas de regresión, rendimiento trazable a specs, observabilidad y recuperación. Registrar revisiones y artefactos realmente desplegados. El despliegue, aplicación de migraciones y ensayo de recuperación son operaciones separadas con sus propias aprobaciones.

Si la recuperación es necesaria, su plan debe ser ejecutable y autorizado; no asumir que rollback de aplicación revierte la base de datos. Documentar compatibilidad y restauración, límites de pérdida aceptados por el responsable y validación posterior. Entrega: `docs/release/staging-validation-report.md`, auditoría G4. Ninguna actividad de esta fase se ejecuta en la inicialización.

## 6. Fases 5A y 5B

### 5A — Preparar candidato, sin tocar producción

Congelar revisiones completas de ambos repositorios, manifestar migraciones y hashes de artefactos, configuración requerida sin secretos, dependencias, compatibilidad, checks previos/posteriores, responsables, ventana propuesta, monitorización y criterios de abortar/recuperar. Documentar backup/restauración y el ensayo comprobado en staging. Completar aceptación de negocio y listado de riesgos con responsables.

Preparar `docs/release/production-release-plan.md`. Para 009, incluir inventario de continuidad de catálogo, URLs, imágenes, precios iniciales y procedimiento de cambio de fuente: si falta una ficha vigente, no cambiar la fuente. Si falta acceso autorizado al inventario real, esa comprobación sigue bloqueada, no se da por satisfecha con fixtures.

G5A puede certificar un candidato preparado según su alcance, pero no autoriza commits, push, publicación, copia real, migraciones remotas ni deploy. La inicialización tampoco ejecuta 5A.

### 5B — Producción con autorización específica

Solo después de G5A habilitante y aprobación humana inequívoca de la operación concreta. Revalidar destino, identidad, revisión, ventana, alcance, precondiciones y respaldo antes de cada paso. Ejecutar una vez, capturar salida/estado, comprobar el efecto y detenerse ante desviaciones. Cada siguiente operación necesita su propio registro; un reintento consume una aprobación nueva.

Tras el despliegue autorizado, realizar únicamente las comprobaciones autorizadas de salud, flujos, auditoría y monitorización. Si procede recuperar, detener el avance y ejecutar solo la recuperación específicamente autorizada. El auditor evalúa G5B sobre efectos reales. Ni «continúa», ni «adelante», ni aprobar un plan/gate constituyen autorización de producción.

## 7. Protocolo de autorización por operación

No hay commits, push, deploy, reset ni copia de datos reales automáticos. La excepción local aprobada en esta sesión se limita a creación/disposición de recursos Docker nuevos `ctt-release-qa...`; no se extiende a resets de Supabase existente ni a entornos remotos.

Antes de un efecto sujeto a autorización, el padre/orquestador persiste el siguiente registro en el estado/decisiones bajo su lock. Completar con valores concretos; una plantilla sin completar no concede permiso:

```text
ID DE APROBACIÓN:
FECHA/HORA Y ZONA:
APROBADOR Y REFERENCIA AL MENSAJE EXPLÍCITO:
AGENTE / FASE / RUN_ID:
OPERACIÓN ÚNICA:
COMANDO EXACTO Y DIRECTORIO DE TRABAJO:
DESTINO (entorno, host/proyecto/cuenta y recursos exactos):
IDENTIDAD / CREDENCIAL EFECTIVA (referencia, nunca secreto):
REPOSITORIO / REVISIÓN / HASH DEL ESTADO DE TRABAJO:
VENTANA DE VALIDEZ (inicio y fin):
ALCANCE MÁXIMO (rutas, recursos, datos, efectos permitidos):
PRECONDICIONES / RESULTADO ESPERADO / CONDICIÓN DE ABORTO:
ESTADO (pendiente / concedida / consumida / vencida / revocada):
CONSUMO (fecha/hora, comando ejecutado, salida y evidencia):
```

La aprobación del usuario debe corresponder a esos valores. Para la excepción Docker ya concedida, enlazar el mensaje de esta sesión y registrar los nombres nuevos exactos antes de cada operación; si el comando excede esa autorización, solicitar aprobación nueva. No inventar hora, vigencia o identidad del aprobador.

Usar permisos de herramienta **solo una vez**; nunca `--auto` ni concesiones persistentes para eludir confirmaciones. Una regla `allow` o una herramienta disponible no sustituye aprobación. Los permisos OpenCode **no son un sandbox**: scripts, procesos hijos, shell, MCP y credenciales heredadas pueden alcanzar destinos externos. Inspeccionar sin exponer secretos el contexto Docker, enlaces de Supabase, variables de destino, remotos y cuentas efectivas antes de ejecutar. Destino/credencial no verificable implica bloqueo. No encadenar varias operaciones sensibles bajo una aprobación genérica.

## 8. Persistencia y reanudación

Los informes se entregan usando la plantilla de AGENT-RESPONSIBILITIES.md. La evidencia nueva va en `docs/orchestration/evidence/<run_id>/<fase>/`, con manifiesto, fecha/hora real, revisión, entorno y referencias a requisitos. Capturas, logs y trazas deben redactar secretos y PII antes de persistirse. Los informes históricos son antecedentes, nunca evidencia de una ejecución nueva.

Al reanudar: leer documentos/estado, verificar revisión y destino, revisar locks y aprobaciones vencidas/consumidas, comprobar que la evidencia corresponde al candidato, e identificar el primer gate no habilitante. No reintentar operaciones mutantes por deducirlas de un informe incompleto. El padre persiste el dictamen textual del auditor **literalmente**, con metadatos separados; el auditor no edita archivos.
