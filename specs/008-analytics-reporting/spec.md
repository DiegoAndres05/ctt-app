# Feature Specification: 008-analytics-reporting

**Feature Branch**: `008-analytics-reporting`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Panel de métricas operacionales, reportes de negocio, análisis de conversión y visor de auditoría derivado de mainspec.md (Capítulos 20, 21, 33)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Embudo Comercial de Conversión (Priority: P1)

Como director o gerente de la agencia, quiero visualizar las métricas del embudo comercial completo (Solicitudes Recibidas → Pre-Reservas Creadas → Disponibilidades Verificadas → Cotizaciones Emitidas → Reservas Confirmadas) para entender la efectividad de las ventas y dónde se están perdiendo oportunidades.

**Why this priority**: Es la métrica fundamental de rendimiento del negocio requerida en el mainspec.

**Independent Test**: Puede probarse simulando transacciones a través de los diferentes estados y consultando el informe del embudo, verificando que los porcentajes y cantidades de conversión por etapa se calculan correctamente.

**Acceptance Scenarios**:

1. **Given** un conjunto de solicitudes y transacciones en el sistema para un período de fechas, **When** el administrador consulta el panel de conversión, **Then** visualiza el gráfico de embudo con las cantidades y porcentajes de conversión de cada etapa del ciclo de vida comercial.
2. **Given** un filtro por canal (Web vs WhatsApp), **When** se aplica el filtro, **Then** el embudo refleja exclusivamente las métricas del canal seleccionado, permitiendo comparar el rendimiento entre canales.

---

### User Story 2 - Métricas de Tiempos y Cuellos de Botella Operativos (Priority: P1)

Como coordinador de operaciones, quiero monitorear los tiempos promedio que toma cada fase (tiempo entre solicitud y primer contacto, tiempo de verificación de cupos, tiempo para emitir cotización), para identificar cuellos de botella y mejorar la agilidad del equipo.

**Why this priority**: La demora en cotizar o verificar disponibilidad es la causa principal de pérdida de ventas en agencias de turismo.

**Independent Test**: Puede probarse calculando el tiempo transcurrido entre marcas temporales de eventos y verificando que el reporte destaca los tiempos promedio y los casos que superan los umbrales de alerta.

**Acceptance Scenarios**:

1. **Given** operaciones realizadas durante la semana, **When** el coordinador consulta el informe de tiempos operativos, **Then** el sistema muestra: tiempo medio de respuesta a solicitud, tiempo medio de verificación por proveedor y tiempo medio de cotización.
2. **Given** solicitudes que llevan más de 24 horas sin asignación o sin verificación, **When** se revisa el panel de alertas, **Then** el sistema las resalta en una sección de "Atención Requerida".

---

### User Story 3 - Reporte Comercial de Ventas y Productos más Demandados (Priority: P2)

Como administrador de la agencia, quiero conocer cuáles experiencias, alojamientos y paquetes son los más solicitados, los más cotizados y los más confirmados, así como los volúmenes monetarios facturados, para tomar decisiones informadas de inventario y promociones.

**Why this priority**: Permite negociar mejores acuerdos con los proveedores más demandados y enfocar el presupuesto de marketing en los productos más rentables.

**Independent Test**: Puede probarse generando el reporte de productos para un rango de fechas y verificando que el ranking de productos coincide con el volumen de ítems asociados a reservas confirmadas.

**Acceptance Scenarios**:

1. **Given** reservas confirmadas en el mes, **When** el administrador genera el reporte de productos, **Then** el sistema lista el top de experiencias y alojamientos por volumen de viajeros y por volumen de ingresos generados.
2. **Given** la necesidad de exportar la información para contabilidad o reuniones gerenciales, **When** el usuario hace clic en exportar reporte, **Then** el sistema genera un archivo estructurado (CSV/Excel) con los datos del período seleccionado.

---

### User Story 4 - Visor Administrativo de Bitácora de Auditoría (Priority: P3)

Como oficial de seguridad o administrador principal, quiero consultar y filtrar la bitácora inmutable de eventos de auditoría (quién inició sesión, quién modificó un precio, quién canceló una reserva, cuándo se cambió un rol), para auditar cualquier irregularidad o disputa operativa.

**Why this priority**: Da cumplimiento a los requerimientos de gobernanza y trazabilidad definidos en la Constitución y mainspec Cap. 20.

**Independent Test**: Puede probarse aplicando filtros por usuario, tipo de evento o rango de fechas en la interfaz de auditoría y validando que los eventos desplegados son completos e inmutables.

**Acceptance Scenarios**:

1. **Given** un administrador en el visor de auditoría, **When** filtra por "Modificación de Precio" o "Cancelación de Reserva", **Then** el sistema lista cronológicamente todos los eventos con el usuario autor, la marca temporal, la IP/origen y el detalle antes/después del cambio.

---

### Edge Cases

- ¿Cómo se manejan períodos con cero solicitudes o reservas? Los gráficos y métricas deben mostrar claramente el estado vacío (sin datos para el período) sin arrojar errores de división por cero en las tasas de conversión.
- ¿Pueden los usuarios con rol Agente ver reportes globales de toda la empresa? Por principio de menor privilegio, los agentes solo ven sus propias estadísticas de ventas; los reportes globales consolidados son exclusivos de Administradores y Coordinadores.
- ¿Cómo impactan las reservas canceladas en los reportes de ingresos? El sistema debe diferenciar claramente "Ingresos Brutos Emitidos", "Ingresos Cancelados/Reembolsados" e "Ingresos Netos Reales".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE calcular y mostrar las tasas de conversión y volumen en el embudo comercial: Solicitudes → Pre-Reservas → Verificaciones → Cotizaciones → Reservas Confirmadas.
- **FR-002**: El sistema DEBE permitir filtrar métricas y reportes por rango de fechas (hoy, semana, mes, año o rango personalizado) y por canal de origen.
- **FR-003**: El sistema DEBE calcular los tiempos medios de ciclo entre las etapas del proceso comercial y alertar sobre solicitudes estancadas.
- **FR-004**: El sistema DEBE generar el ranking de productos más cotizados y más reservados (por número de reservas e importe económico).
- **FR-005**: El sistema DEBE proporcionar a los Administradores un visor de auditoría para consultar los registros inmutables de seguridad y operaciones críticas.
- **FR-006**: El sistema DEBE permitir la exportación de reportes tabulares en formato CSV estándar.
- **FR-007**: El sistema DEBE restringir el acceso a los informes financieros y de auditoría exclusivamente a los roles con permisos de supervisión/administración.

### Key Entities

- **Métrica de Conversión**: Registro agregado de rendimiento del embudo para un intervalo de tiempo y canal.
- **Resumen Financiero de Ventas**: Agregación de ingresos por moneda, productos confirmados, saldos recaudados y pendientes.
- **Visor de Auditoría**: Interfaz de consulta de eventos de seguridad y negocio generados por el motor de auditoría.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Carga del panel principal de métricas y gráficos en menos de 2 segundos.
- **SC-002**: 100% de coherencia entre los totales monetarios del reporte de ventas y la suma de reservas confirmadas activas.
- **SC-003**: Cero errores de cálculo en tasas porcentuales de conversión bajo cualquier combinación de filtros.
- **SC-004**: Exportación de reportes de hasta 10,000 registros generada en menos de 5 segundos.

## Assumptions

- Para el MVP inicial, los reportes se calculan mediante consultas agregadas directas optimizadas sobre la base de datos transaccional (no se requiere un Data Warehouse o lago de datos separado en esta fase).
