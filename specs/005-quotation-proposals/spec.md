# Feature Specification: 005-quotation-proposals

**Feature Branch**: `005-quotation-proposals`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "Elaboración, cálculo, emisión y seguimiento de cotizaciones comerciales derivado de mainspec.md (Capítulos 8, 12, 15)."

## Clarifications

### Session 2026-10-04

- Q: ¿Cómo calcula el sistema el precio de cada línea de la cotización y dónde reside la autoridad del cálculo? → A: La autoridad del cálculo vive en el servidor: cada línea se calcula a partir de las tarifas vigentes del catálogo (feature 002) según su tipo de cobro (por persona, por noche, por grupo; complementos por su unidad), para las fechas y pasajeros de la línea de la pre-reserva. El borrador se recalcula en el servidor ante cada cambio; al emitir, los importes quedan congelados en la cotización. La interfaz nunca calcula totales: solo muestra el desglose que devuelve el servidor. Los impuestos son un porcentaje configurable por línea (0 % por defecto) y se desglosan por separado.
- Q: ¿Cuál es la vigencia por defecto de una cotización, cómo se limita por las retenciones de los proveedores y qué ocurre si la pre-reserva cambia o expira después de emitida? → A: Vigencia por defecto de 48 horas desde la emisión, editable por el agente hasta un máximo de 30 días, y nunca posterior a la retención más próxima registrada en la pre-reserva (si existe). Al registrar la aceptación —por el cliente o por el agente— el sistema revalida la elegibilidad de la pre-reserva con la regla de la feature 004: si la pre-reserva expiró, fue cancelada o sus líneas principales cambiaron después de la emisión, la aceptación se rechaza y la cotización pasa a "Expirada", exigiendo una nueva versión.
- Q: ¿El cliente puede aceptar o rechazar la cotización desde la vista pública compartida, o solo el agente registra la respuesta? → A: Ambos. El cliente puede aceptar desde el enlace público con una confirmación explícita (doble paso) y ve instrucciones para contactar a la agencia si quiere cambios; el agente puede registrar desde el panel cualquier respuesta: Aceptada, Rechazada o Requiere modificaciones. Toda respuesta queda auditada con su origen (cliente o agente).
- Q: ¿Qué ajustes comerciales (descuentos o suplementos) se permiten sobre el precio calculado y quién los autoriza? → A: Ajustes por línea y ajustes globales, cada uno en porcentaje o en monto fijo, en sentido descuento o suplemento, con una etiqueta descriptiva obligatoria. Un agente puede ajustar hasta un 15 % acumulado sobre el total calculado; por encima de ese tope, o cualquier ajuste sobre una cotización ya emitida (vía nueva versión), solo lo autoriza un Administrador. Todo ajuste aparece en el desglose visible para el cliente y queda en auditoría.
- Q: ¿Cómo se protege el acceso a la vista pública de la cotización que se comparte con el cliente? → A: Mediante una URL pública con un token opaco no adivinable propio de cada cotización, sin inicio de sesión. La vista es de solo lectura y muestra siempre la versión vigente, con datos mínimos (itinerario, inclusiones/exclusiones, desglose y condiciones; nunca datos internos ni de otros clientes). El token deja de funcionar cuando la cotización se anula.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generación y Cálculo de Cotización (Priority: P1)

Como agente comercial, quiero generar una cotización formal a partir de una pre-reserva verificada, aplicando las tarifas vigentes, sumando complementos, descuentos o suplementos aplicables, para presentar al cliente una propuesta clara con desglose financiero exacto.

**Why this priority**: La cotización es el instrumento comercial fundamental donde la agencia fija el precio y las condiciones de la venta.

**Independent Test**: Puede probarse creando una cotización a partir de una pre-reserva con tarifas parametrizadas, verificando el subtotal por ítem, impuestos/tasas aplicables, descuentos y el total final calculado por el servidor sin discrepancias.

**Acceptance Scenarios**:

1. **Given** una pre-reserva verificada, **When** el agente genera la cotización, **Then** el sistema calcula en el servidor los importes según la lista de precios vigente para las fechas y número de viajeros solicitados, y muestra el desglose por línea con su tipo de cobro.
2. **Given** una cotización en borrador, **When** el agente añade un descuento comercial dentro de su tope o un add-on adicional, **Then** el servidor recalcula el total y registra el desglose transparente de cada concepto; si el ajuste supera el tope del 15 % acumulado, el sistema lo rechaza indicando que requiere un Administrador.
3. **Given** una cotización generada, **When** se emite oficialmente, **Then** el sistema le asigna un número consecutivo único (COT-#####) con su número de versión y congela los valores monetarios frente a futuros cambios de catálogo.

---

### User Story 2 - Definición de Términos y Vigencia de la Oferta (Priority: P1)

Como agente comercial o administrador, quiero que cada cotización cuente con una fecha y hora límite de validez (vigencia), políticas de cancelación y condiciones de pago, para proteger a la agencia frente a fluctuaciones de costos o pérdida de disponibilidad de los proveedores.

**Why this priority**: Los cupos y tarifas con hoteles o transportistas caducan; una cotización no puede ser eterna.

**Independent Test**: Puede probarse emitiendo una cotización con la vigencia por defecto de 48 horas y verificando que, tras expirar el plazo sin aceptación del cliente, la cotización pasa a estado "Expirada" impidiendo su aceptación directa.

**Acceptance Scenarios**:

1. **Given** una cotización emitida con vigencia de 48 horas (o la editada por el agente dentro del tope de retención y 30 días), **When** el cliente acepta la propuesta dentro del plazo y la pre-reserva sigue elegible, **Then** la cotización pasa a "Aceptada" y habilita la creación de la Reserva Confirmada (feature 006).
2. **Given** una cotización cuyo plazo de vigencia ha expirado, o cuya pre-reserva expiró o cambió de líneas después de la emisión, **When** se consulta o se intenta aceptar, **Then** el sistema indica que la cotización está expirada y requiere una nueva versión con tarifas y disponibilidad re-verificadas.
3. **Given** un agente que intenta fijar una vigencia posterior a la retención más próxima de la pre-reserva, **When** guarda, **Then** el sistema lo rechaza indicando la fecha máxima permitida.

---

### User Story 3 - Emisión y Entrega Multicanal de la Propuesta (Priority: P2)

Como agente comercial, quiero generar un resumen atractivo de la propuesta (en formato descargable/imprimible o enlace web accesible y resumen estructurado para WhatsApp) para hacérselo llegar al cliente por su canal preferido.

**Why this priority**: La presentación visual y la facilidad de lectura de la propuesta determinan en gran medida la tasa de conversión comercial.

**Independent Test**: Puede probarse generando el enlace público con token de la cotización y verificando que la vista de cliente presenta el itinerario, las inclusiones/exclusiones, el precio desglosado y el botón de aceptación con confirmación, todo adaptado a móvil.

**Acceptance Scenarios**:

1. **Given** una cotización emitida, **When** el agente solicita el formato para WhatsApp, **Then** el sistema genera un texto formateado con emojis, resumen de itinerario, total y enlace a la cotización detallada.
2. **Given** el enlace público con token compartido con el cliente, **When** el cliente abre la página de la cotización, **Then** visualiza la información de su viaje de forma clara y adaptada a dispositivos móviles, con el botón «Aceptar propuesta» que exige una confirmación explícita.
3. **Given** una cotización anulada, **When** alguien abre su enlace público, **Then** el sistema muestra que la propuesta ya no está disponible, sin exponer datos.

---

### User Story 4 - Registro de Respuestas del Cliente y Versionado (Priority: P3)

Como agente comercial, quiero registrar la respuesta del cliente (Aceptada, Rechazada, Requiere Modificaciones) y generar una nueva versión de la cotización si solicita cambios, para mantener el historial de la negociación sin perder la versión previa.

**Why this priority**: Las negociaciones turísticas suelen iterar 2 o 3 veces antes del acuerdo final; el historial de versiones evita malentendidos.

**Independent Test**: Puede probarse modificando una cotización emitida, comprobando que se genera la versión 2 (ej. COT-00001-v2) manteniendo intacta la versión 1 (COT-00001-v1), que queda marcada como "Superada por nueva versión".

**Acceptance Scenarios**:

1. **Given** una cotización emitida (v1), **When** el cliente pide cambiar de hotel o fecha, **Then** el agente crea una versión nueva (v2), heredando los datos base y marcando la v1 como "Superada por nueva versión"; la vista pública con el mismo token muestra a partir de ese momento la v2.
2. **Given** una cotización que el cliente acepta formalmente (desde el enlace o por registro del agente), **When** se confirma la aceptación y la pre-reserva sigue elegible, **Then** la cotización cambia de estado a "Aceptada" registrando el origen de la respuesta y habilita la creación de la Reserva Confirmada (feature 006).
3. **Given** una cotización en estado "Aceptada", **When** se evalúan las acciones disponibles, **Then** el sistema impide crear nuevas versiones o editarla: es terminal para la negociación.

---

### Edge Cases

- ¿Qué sucede si un ítem de la pre-reserva expira antes de la vigencia global de la cotización? La vigencia de la cotización no puede ser posterior a la retención más próxima registrada en la pre-reserva; el sistema impone ese tope al emitir y lo indica.
- ¿Qué sucede si la pre-reserva cambia (líneas agregadas, retiradas o promovidas) o expira después de emitida la cotización? Al intentar registrar la aceptación, el sistema revalida la elegibilidad con la regla de la feature 004; si ya no es elegible, rechaza la aceptación y marca la cotización como "Expirada", exigiendo una nueva versión.
- ¿Cómo se manejan cotizaciones con monedas diferentes a la local? La cotización registra una sola moneda (por defecto la de la organización); si difiere de la moneda local, se congela la tasa de cambio de referencia al momento de la emisión. Todas las líneas de una cotización comparten la misma moneda.
- ¿Puede cancelarse una cotización emitida si la agencia detecta un error de cálculo? Sí, un usuario con permisos de administrador puede anularla registrando el motivo en auditoría; el enlace público deja de funcionar.
- ¿Qué ocurre si el cliente abre dos veces el enlace o reenvía el token? La vista es de solo lectura y muestra siempre la versión vigente; la aceptación exige confirmación explícita y solo es válida una vez: una cotización ya "Aceptada", "Anulada" o "Expirada" muestra su estado y no permite otra aceptación.
- ¿Qué ocurre si el catálogo cambia de precios después de emitida la cotización? Nada: los importes emitidos están congelados. Los cambios de tarifa solo aplican a nuevas versiones o nuevas cotizaciones.
- ¿Qué ocurre con las versiones anteriores cuando se emite una nueva? Quedan intactas en solo lectura, marcadas como "Superada por nueva versión", y no admiten aceptación.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir crear Cotizaciones Comerciales asociadas a una Pre-Reserva elegible según la regla de la feature 004 (verificada o con excepción de Administrador vigente) y a un Cliente.
- **FR-002**: El sistema DEBE calcular en el servidor cada línea de cotización a partir de las tarifas vigentes del catálogo (feature 002) según el tipo de cobro del producto o complemento, y desglosar: producto/servicio, fecha, cantidad, precio unitario, impuestos (porcentaje configurable por línea, 0 % por defecto), ajustes (descuentos/suplementos) e importe neto. La interfaz NO DEBE calcular totales.
- **FR-003**: El sistema DEBE asignar a cada cotización un código de referencia consecutivo único por organización (ej. COT-00001) y número de versión (v1, v2, …); las versiones comparten la referencia.
- **FR-004**: Toda cotización DEBE tener fecha y hora límite de vigencia: por defecto 48 horas desde la emisión, editable hasta un máximo de 30 días y nunca posterior a la retención más próxima de la pre-reserva (si existe). Vencida sin aceptación, pasa a "Expirada".
- **FR-005**: El sistema DEBE soportar los estados de cotización: Borrador, Emitida/Enviada, Aceptada, Rechazada, Expirada y Anulada; además, una versión reemplazada queda en solo lectura como "Superada por nueva versión". "Aceptada" y "Anulada" son terminales.
- **FR-006**: El sistema DEBE permitir versionar cotizaciones cuando el cliente solicite ajustes o cambios de itinerario, heredando los datos base y marcando la versión anterior como "Superada por nueva versión".
- **FR-007**: El sistema DEBE generar una vista pública de cliente accesible por URL con token opaco por cotización (sin login, solo lectura, siempre la versión vigente, datos mínimos), un formato imprimible/descargable y un formato de texto optimizado para envío por WhatsApp. El token DEBE dejar de funcionar al anular la cotización.
- **FR-008**: El sistema DEBE congelar los valores económicos de una cotización en estado Emitida (incluida la tasa de cambio de referencia si la moneda difiere de la local); cualquier cambio posterior exige una nueva versión.
- **FR-009**: El sistema DEBE permitir ajustes comerciales (descuento o suplemento, por línea o global, en porcentaje o monto fijo, con etiqueta obligatoria): un agente hasta el 15 % acumulado sobre el total calculado; por encima solo un Administrador. Todo ajuste DEBE verse en el desglose del cliente y registrarse en auditoría.
- **FR-010**: El sistema DEBE permitir al cliente aceptar la propuesta desde la vista pública con confirmación explícita, y al agente registrar la respuesta (Aceptada, Rechazada, Requiere modificaciones). Al registrar la aceptación, el sistema DEBE revalidar la elegibilidad de la pre-reserva (feature 004): si ya no es elegible, rechaza la aceptación y marca la cotización como "Expirada". Toda respuesta DEBE registrarse con su origen (cliente o agente) en auditoría.
- **FR-011**: Al registrar "Requiere modificaciones", el sistema DEBE sugerir la creación de una nueva versión; las solicitudes de cambio del cliente se atienden siempre con una versión nueva, nunca editando la emitida.
- **FR-012**: El sistema DEBE permitir a un Administrador anular una cotización no aceptada, con motivo obligatorio registrado en auditoría e invalidación del enlace público.

### Key Entities

- **Cotización**: Propuesta comercial vinculante con plazo determinado. Atributos: ID, OrganizaciónID, ReferenciaConsecutiva (COT-#####), Versión (1, 2, ...), ClienteID, PreReservaID, AgenteID, Moneda, TasaCambioReferencia (si aplica), MontoSubtotal, Impuestos, Ajustes, MontoTotal, FechaEmisión, FechaVencimiento, Estado (Borrador, Emitida, Aceptada, Rechazada, Expirada, Anulada, Superada), TokenPúblico, RespuestaOrigen (cliente/agente), TérminosYCondiciones, NotasComerciales.
- **Ítem de Cotización**: Línea de producto o servicio dentro de la cotización, con importes congelados al emitir. Atributos: ID, CotizaciónID, DescripciónServicio, ProductoID o ComplementoID (opcional), LíneaPreReservaID, FechaInicio, FechaFin, Cantidad, Pasajeros, TipoCobro, PrecioUnitario, PorcentajeImpuesto, AjustesLínea, ImporteTotalLínea.
- **Ajuste Comercial**: Descuento o suplemento aplicado a una línea o al total. Atributos: ID, CotizaciónID, ÍtemID (opcional), Etiqueta, Sentido (descuento/suplemento), Tipo (porcentaje/monto), Valor, AutorID.
- **Versión de Cotización**: Instancia inmutable de la cotización tras emitirse; la cotización agrupa sus versiones y solo una es la vigente.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Tiempo promedio de armado y emisión de una cotización estándar menor a 3 minutos desde una pre-reserva verificada.
- **SC-002**: 100% de coherencia matemática en totales, subtotales, impuestos y ajustes (0 discrepancias por redondeo o cálculos manuales; el cálculo vive en una sola autoridad en el servidor).
- **SC-003**: 100% de las cotizaciones emitidas poseen fecha de vencimiento dentro de los topes permitidos y términos comerciales explícitos.
- **SC-004**: La propuesta web de cliente es 100% responsive y legible en dispositivos móviles sin requerir instalación de software adicional, y el 100% de los accesos públicos se realizan mediante token no adivinable sin exponer datos internos.
- **SC-005**: 0 cotizaciones aceptadas sobre pre-reservas expiradas, canceladas o modificadas después de la emisión (revalidación sistemática en la aceptación).

## Assumptions

- No se requiere una pasarela de pago en línea compleja automatizada para el MVP; la confirmación y pago se soportan con verificación manual de comprobantes/anticipos (según Cap. 31 diferido).
- La emisión de cotizaciones no genera facturación electrónica fiscal en este MVP.
- Los términos y condiciones comerciales son un texto configurable por cotización con una plantilla por defecto de la organización.
- La generación de la Reserva Confirmada a partir de la cotización aceptada pertenece a la feature 006; esta feature solo habilita ese paso dejando la cotización en estado "Aceptada".
