# Feature Specification: 005-quotation-proposals

**Feature Branch**: `005-quotation-proposals`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Elaboración, cálculo, emisión y seguimiento de cotizaciones comerciales derivado de mainspec.md (Capítulos 8, 12, 15)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generación y Cálculo de Cotización (Priority: P1)

Como agente comercial, quiero generar una cotización formal a partir de una pre-reserva verificada, aplicando las tarifas vigentes, sumando complementos, descuentos o suplementos aplicables, para presentar al cliente una propuesta clara con desglose financiero exacto.

**Why this priority**: La cotización es el instrumento comercial fundamental donde la agencia fija el precio y las condiciones de la venta.

**Independent Test**: Puede probarse creando una cotización a partir de una pre-reserva con tarifas parametrizadas, verificando el subtotal por ítem, impuestos/tasas aplicables, descuentos y el total final calculado sin discrepancias.

**Acceptance Scenarios**:

1. **Given** una pre-reserva verificada, **When** el agente genera la cotización, **Then** el sistema calcula automáticamente los importes según la lista de precios vigente para las fechas y número de viajeros solicitados.
2. **Given** una cotización en borrador, **When** el agente añade un descuento comercial autorizado o un add-on adicional, **Then** el sistema recalcula el total y registra el desglose transparente de cada concepto.
3. **Given** una cotización generada, **When** se emite oficialmente, **Then** el sistema le asigna un número consecutivo único y congela los valores monetarios frente a futuros cambios de catálogo.

---

### User Story 2 - Definición de Términos y Vigencia de la Oferta (Priority: P1)

Como agente comercial o administrador, quiero que cada cotización cuente con una fecha y hora límite de validez (vigencia), políticas de cancelación y condiciones de pago, para proteger a la agencia frente a fluctuaciones de costos o pérdida de disponibilidad de los proveedores.

**Why this priority**: Los cupos y tarifas con hoteles o transportistas caducan; una cotización no puede ser eterna.

**Independent Test**: Puede probarse configurando una fecha de vigencia en la cotización y verificando que, tras expirar el plazo sin aceptación del cliente, la cotización pasa automáticamente a estado "Expirada" impidiendo su confirmación directa.

**Acceptance Scenarios**:

1. **Given** una cotización emitida con vigencia de 48 horas, **When** el cliente intenta aceptar la propuesta dentro del plazo, **Then** la cotización se encuentra en estado "Vigente / Enviada" y permite proceder al pago o confirmación.
2. **Given** una cotización cuyo plazo de vigencia ha expirado, **When** se consulta o se intenta confirmar, **Then** el sistema notifica que la cotización está expirada y requiere re-verificación de tarifas y disponibilidad.

---

### User Story 3 - Emisión y Entrega Multicanal de la Propuesta (Priority: P2)

Como agente comercial, quiero generar un resumen atractivo de la propuesta (en formato descargable/imprimible o enlace web accesible y resumen estructurado para WhatsApp) para hacérselo llegar al cliente por su canal preferido.

**Why this priority**: La presentación visual y la facilidad de lectura de la propuesta determinan en gran medida la tasa de conversión comercial.

**Independent Test**: Puede probarse generando el enlace o vista de cliente de la cotización y verificando que presenta el itinerario, las inclusiones/exclusiones, el precio desglosado y el botón o instrucción clara de aceptación.

**Acceptance Scenarios**:

1. **Given** una cotización emitida, **When** el agente solicita el formato para WhatsApp, **Then** el sistema genera un texto formateado con emojis, resumen de itinerario, total y enlace a la cotización detallada.
2. **Given** el enlace de la propuesta compartida con el cliente, **When** el cliente abre la página de la cotización, **Then** visualiza la información de su viaje de forma clara y adaptada a dispositivos móviles.

---

### User Story 4 - Registro de Respuestas del Cliente y Versionado (Priority: P3)

Como agente comercial, quiero registrar la respuesta del cliente (Aceptada, Rechazada, Requiere Modificaciones) y generar una nueva versión de la cotización si solicita cambios, para mantener el historial de la negociación sin perder la versión previa.

**Why this priority**: Las negociaciones turísticas suelen iterar 2 o 3 veces antes del acuerdo final; el historial de versiones evita malentendidos.

**Independent Test**: Puede probarse modificando una cotización emitida, comprobando que se genera la versión 2 (ej. COT-1001-v2) manteniendo intacta la versión 1 (COT-1001-v1).

**Acceptance Scenarios**:

1. **Given** una cotización emitida (v1), **When** el cliente pide cambiar de hotel o fecha, **Then** el agente crea una versión nueva (v2), heredando los datos base y marcando la v1 como "Superada por nueva versión".
2. **Given** una cotización que el cliente acepta formalmente, **When** el agente marca "Aceptada por el cliente", **Then** la cotización cambia de estado a "Aceptada" y habilita la creación de la Reserva Confirmada.

---

### Edge Cases

- ¿Qué sucede si un ítem de la pre-reserva expira antes de la vigencia global de la cotización? La vigencia de la cotización no puede ser posterior a la fecha límite impuesta por el proveedor más restrictivo.
- ¿Cómo se manejan cotizaciones con monedas diferentes a la local? El sistema debe registrar la moneda de la cotización y la tasa de cambio de referencia utilizada al momento de la emisión.
- ¿Puede cancelarse una cotización emitida si la agencia detecta un error de cálculo? Sí, un usuario con permisos de supervisor puede anularla registrando el motivo en auditoría.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir crear Cotizaciones Comerciales asociadas a una Pre-Reserva y a un Cliente.
- **FR-002**: El sistema DEBE desglosar cada línea de cotización: producto/servicio, fecha, cantidad, precio unitario, recargos/descuentos e importe neto.
- **FR-003**: El sistema DEBE asignar a cada cotización un código de referencia consecutivo (ej. COT-0001) y número de versión.
- **FR-004**: Toda cotización DEBE incluir una fecha y hora límite de vigencia obligatoria.
- **FR-005**: El sistema DEBE soportar los estados de cotización: Borrador, Emitida/Enviada, Aceptada, Rechazada, Expirada y Anulada.
- **FR-006**: El sistema DEBE permitir clonar o versionar cotizaciones cuando el cliente solicite ajustes o cambios de itinerario.
- **FR-007**: El sistema DEBE generar una vista resumen para el cliente accesible por enlace y un formato de texto optimizado para envío por WhatsApp.
- **FR-008**: El sistema DEBE congelar los valores económicos de una cotización en estado Emitida; cualquier cambio posterior exige una nueva versión.

### Key Entities

- **Cotización**: Propuesta comercial vinculante con plazo determinado. Atributos: ID, OrganizaciónID, ReferenciaConsecutiva, Versión (1, 2, ...), ClienteID, PreReservaID, AgenteID, Moneda, MontoSubtotal, Descuentos, Impuestos, MontoTotal, FechaEmisión, FechaVencimiento, Estado (Borrador, Enviada, Aceptada, Rechazada, Expirada, Anulada), TérminosYCondiciones, NotasComerciales.
- **Ítem de Cotización**: Línea de producto o servicio dentro de la cotización. Atributos: ID, CotizaciónID, DescripciónServicio, ProductoID (opcional), FechaInicio, FechaFin, Cantidad, PrecioUnitario, DescuentoLínea, ImporteTotalLínea.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Tiempo promedio de armado y emisión de una cotización estándar menor a 3 minutos desde una pre-reserva verificada.
- **SC-002**: 100% de coherencia matemática en totales, subtotales y descuentos (0 discrepancias por redondeo o cálculos manuales).
- **SC-003**: 100% de las cotizaciones emitidas poseen fecha de vencimiento y términos comerciales explícitos.
- **SC-004**: La propuesta web de cliente es 100% responsive y legible en dispositivos móviles sin requerir instalación de software adicional.

## Assumptions

- No se requiere una pasarela de pago en línea compleja automatizada para el MVP; la confirmación y pago se soportan con verificación manual de comprobantes/anticipos (según Cap. 31 diferido).
- La emisión de cotizaciones no genera facturación electrónica fiscal en este MVP.
