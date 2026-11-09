# Informe de cambios recientes — CTTAdmin

**Fecha del informe:** 3 de noviembre de 2026  
**Periodo revisado:** 1–27 de octubre de 2026  
**Repositorio:** `DiegoAndres05/ctt-app`  
**Base técnica:** Angular 22 standalone, Signals, Supabase/PostgreSQL y RLS multi-tenant

## 1. Resumen ejecutivo

Durante el último ciclo se consolidó el flujo comercial principal de la aplicación:

1. recepción y gestión de solicitudes de clientes;
2. creación de pre-reservas y verificación humana de disponibilidad;
3. elaboración y envío de cotizaciones con precios calculados en servidor;
4. confirmación y operación de reservas;
5. visualización de métricas, reportes y auditoría;
6. reorganización del panel administrativo y su navegación.

El cambio más reciente, del 27 de octubre, reforzó el shell administrativo, el menú lateral y el dashboard. El resultado es una base más completa para la operación diaria de la agencia, manteniendo las reglas de autorización y los cálculos sensibles en Supabase.

## 2. Cambios incluidos

### 2.1. Gestión de reservas y ciclo operativo

Se implementó el módulo de reservas (`006`), que convierte una cotización aceptada en una reserva confirmada con referencia `RSV-#####`.

Incluye:

- confirmación desde una cotización aceptada;
- registro de depósitos manuales y abonos adicionales;
- ciclo de estados `confirmed → in_progress → completed`;
- cancelación controlada y creación de nuevas versiones;
- órdenes de servicio por proveedor;
- comprobante público mediante voucher con token hash;
- auditoría de las operaciones relevantes;
- vistas internas que no exponen token, documentos ni datos innecesarios.

La interfaz muestra los importes persistidos por el servidor (`paid_total` y `balance`), sin recalcular dinero en Angular.

### 2.2. Cotizaciones y propuestas comerciales

El módulo de cotizaciones (`005`) quedó conectado con las pre-reservas y las reservas:

- cálculo de tarifas, impuestos, descuentos y recargos en PostgreSQL;
- congelamiento del importe al emitir una cotización;
- vigencia y expiración gestionadas por el servidor;
- enlace público de solo lectura;
- aceptación pública con confirmación explícita;
- versionado de propuestas;
- invalidación mediante razón;
- revalidación cuando cambia la pre-reserva o queda obsoleta;
- generación de texto para WhatsApp sin enviar mensajes desde Angular.

Los tokens públicos se almacenan únicamente como hash en la base de datos y se entregan en claro una sola vez.

### 2.3. Pre-reservas y verificación de disponibilidad

El módulo de pre-reservas (`004`) consolidó la cola de trabajo para verificar disponibilidad con proveedores.

Se incorporaron:

- creación de pre-reservas desde solicitudes;
- asignación de responsables;
- verificación por línea de servicio;
- registro histórico de disponibilidad, alternativas y retiros;
- expiración de retenciones de proveedores;
- promoción de alternativas;
- estados derivados por la base de datos;
- control de elegibilidad para cotizar;
- excepción administrativa auditada para cotizar cuando aún no se ha verificado todo.

La aplicación no trata una pre-reserva como una reserva confirmada, una retención de inventario ni un precio definitivo.

### 2.4. Solicitudes de clientes y canales de entrada

El módulo de solicitudes (`003`) estableció la entrada multicanal:

- formulario web público;
- WhatsApp mediante Edge Function;
- captura asistida por teléfono o atención presencial;
- deduplicación e idempotencia;
- validación de consentimiento y datos de contacto;
- asignación, seguimiento y descarte con motivo;
- notas internas;
- anonimización de clientes por parte de administradores.

El webhook de WhatsApp valida la firma HMAC de Meta antes de procesar el mensaje. La aplicación Angular no almacena secretos de proveedores ni envía mensajes salientes.

### 2.5. Reportes, métricas y auditoría

Se incorporó el alcance de analítica operativa (`008`):

- embudo comercial;
- tiempos operativos;
- cola de casos pendientes;
- ranking de productos;
- resumen de ventas;
- exportación CSV;
- widgets de resumen en el dashboard;
- filtros de auditoría para eventos de solicitudes, cotizaciones y reservas.

Las tasas, conteos y totales se calculan mediante RPCs de PostgreSQL. La UI se limita a presentar el JSON recibido y no realiza cálculos comerciales.

### 2.6. Shell administrativo y navegación

El último commit reforzó la experiencia del panel:

- nuevo `AdminShellComponent` para concentrar navegación, identidad y contenido;
- sidebar colapsable en escritorio;
- drawer responsive en pantallas estrechas;
- backdrop y cierre automático del menú después de navegar;
- persistencia de la preferencia de sidebar;
- barra superior con usuario, rol y organización;
- cierre de sesión centralizado;
- aviso visible cuando una ruta deniega permisos;
- integración de la notificación de pre-reservas verificadas;
- dashboard ampliado con resumen operativo y accesos rápidos.

## 3. Decisiones técnicas relevantes

- **Seguridad por defecto:** RLS por `organization_id`, RPCs `SECURITY DEFINER` y validación de rol en servidor.
- **Separación de responsabilidades:** Angular presenta datos; Supabase valida permisos, calcula importes y cambia estados.
- **Trazabilidad:** los cambios operativos importantes se registran en auditoría y los eventos históricos críticos son append-only.
- **Privacidad:** las vistas de listado excluyen tokens, teléfonos, correos y otros datos que no son necesarios para cada operación.
- **Sin servicios externos innecesarios:** no se añadió data warehouse, pasarela de pagos ni envío automático de WhatsApp/correo.
- **Compatibilidad multi-tenant:** las operaciones y referencias se aíslan por organización.

## 4. Evidencia y validación disponible

La documentación del proyecto registra:

- suites SQL de RLS y comportamiento para solicitudes, pre-reservas, cotizaciones, reservas y analítica;
- validación local de migraciones de analítica;
- quickstart del módulo de reservas con confirmación, ciclo operativo, órdenes de proveedor y voucher;
- quickstart de reportes con embudo, tiempos, ranking y límite de rango de 366 días;
- escenarios de solicitudes con pruebas SQL, aunque varios escenarios de navegador aún figuran como no ejecutados;
- soporte de build, lint, formato y pruebas desde los scripts del proyecto.

La revisión del historial se realizó sobre un estado sin cambios locales pendientes; el único archivo añadido por este trabajo es este informe.

## 5. Aspectos pendientes o recomendaciones

1. Ejecutar nuevamente el build, lint, formato y las suites SQL en un entorno con Docker disponible.
2. Completar la validación de navegador de los escenarios pendientes del módulo de solicitudes.
3. Ejecutar una confirmación de reserva sobre datos de demostración para poblar ventas y validar el ranking de productos con datos no vacíos.
4. Revisar la accesibilidad del drawer y del sidebar en dispositivos reales, especialmente foco de teclado y lectores de pantalla.
5. Mantener sincronizados los documentos de cada módulo y los quickstarts cuando cambien los estados o rutas.
6. Antes de producción, comprobar la configuración de hooks de Supabase, variables del webhook de WhatsApp y políticas de almacenamiento de comprobantes.

## 6. Commits revisados

| Commit | Fecha | Cambio |
|---|---:|---|
| `63def24` | 2026-10-27 | Mejora del shell administrativo, sidebar y dashboard |
| `8135ce5` | 2026-10-26 | Implementación del módulo de reservas y su ciclo de vida |
| `4617093` | 2026-10-16 | Documentación de reservas y navegación relacionada |
| `fd38483` | 2026-10-12 | Cotizaciones con precios en servidor y token público |
| `a1a8b70` | 2026-10-12 | Pre-reservas y verificación humana de disponibilidad |
| `2cb45f1` | 2026-10-04 | Solicitudes de clientes por web, WhatsApp y captura manual |
| `fa26428` | 2026-10-16 | Dockerfile, Docker Compose y configuración de entorno |
| `f419ec5` | 2026-10-01 | Integración del layout administrativo y actualizaciones de CMS |

## 7. Conclusión

El proyecto pasó de contar principalmente con la base de autenticación y acceso multi-tenant a disponer de un flujo operativo comercial mucho más completo. La prioridad del siguiente ciclo debería ser cerrar la validación integral —especialmente navegador y despliegue— y probar el flujo completo con datos representativos, antes de ampliar el alcance funcional.
