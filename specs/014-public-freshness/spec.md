# Feature Specification: Frescura de lo que ve el viajero

**Feature Branch**: `014-public-freshness`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Iteración 4 de 5. Lo que el viajero ve en el catálogo y en el contenido editorial se actualiza pronto, las visitas repetidas no se sienten lentas, y una copia guardada nunca decide disponibilidad ni precio final (`.specify/mainspec.md`, capítulo 26).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver un cambio del catálogo sin esperar al día siguiente (Priority: P1)

Como operador, quiero que al publicar, despublicar, marcar agotado o corregir el precio de vitrina, un viajero que entra de nuevo vea ese cambio pronto, para no vender con una vitrina vieja.

**Why this priority**: Una vitrina atrasada contradice el principio de que la existencia en catálogo no es disponibilidad y de que el precio mostrado es el que la agencia acaba de publicar.

**Independent Test**: Se publica una ficha nueva y otra se despublica. Una visita nueva, hecha dentro de los cinco minutos, muestra la primera y ya no muestra la segunda.

**Acceptance Scenarios**:

1. **Given** una ficha que acaba de publicarse, **When** un visitante abre el catálogo dentro de los cinco minutos siguientes, **Then** la ficha aparece con el texto y el precio de vitrina recién guardados.
2. **Given** una ficha que acaba de despublicarse o cuyo producto quedó inactivo, **When** un visitante abre el catálogo o la dirección anterior dentro de los cinco minutos, **Then** ya no la encuentra.
3. **Given** una ficha marcada como agotada, **When** un visitante la abre dentro de los cinco minutos, **Then** ve la marca de agotado.

---

### User Story 2 - Volver a una página sin empezar de cero (Priority: P2)

Como visitante que recorre varias fichas o reabre el blog en la misma visita, quiero que las páginas que ya vi respondan de inmediato, para poder comparar sin esperas largas.

**Why this priority**: El capítulo 26 pide buen rendimiento en páginas estables. No puede lograrse a costa de mostrar un viaje que ya se retiró.

**Independent Test**: En la misma visita, abrir dos veces la misma ficha publicada muestra el mismo contenido la segunda vez sin una espera perceptible, y un cambio de publicación hecho por la agencia sigue respetando la ventana de cinco minutos de la historia 1.

**Acceptance Scenarios**:

1. **Given** un visitante que ya abrió una ficha en esa visita, **When** vuelve a abrirla antes de que la agencia la cambie, **Then** la ve de nuevo sin una espera comparable a la primera carga.
2. **Given** un artículo ya leído en esa visita, **When** el visitante regresa al blog, **Then** el listado reaparece de inmediato mientras el gestor editorial siga sano.

---

### User Story 3 - La copia guardada no cierra una venta (Priority: P1)

Como agencia, quiero que la rapidez del sitio no convierta un precio de vitrina ni un texto guardado en disponibilidad confirmada o en precio final.

**Why this priority**: El capítulo 26 prohíbe que una copia sea la fuente de verdad de disponibilidad, estado de reserva o precio comprometido.

**Independent Test**: Con la vitrina mostrando un precio, el agente emite una cotización por otro valor. El viajero, en la propuesta, ve el valor de la cotización. La ficha pública sigue mostrando solo el precio de vitrina.

**Acceptance Scenarios**:

1. **Given** un precio de vitrina distinto del precio de una cotización ya emitida, **When** el viajero abre la propuesta por su enlace, **Then** ve el precio de la propuesta, no el de la vitrina.
2. **Given** una ficha agotada que un visitante todavía alcanzó a solicitar, **When** el agente revisa el caso, **Then** la solicitud sigue siendo una petición por verificar, no una reserva.
3. **Given** el gestor editorial caído y una copia reciente de un artículo, **When** el visitante abre el blog, **Then** puede ver esa copia reciente marcada como posiblemente desactualizada, o el aviso de no disponibilidad de la iteración 3. El catálogo y la solicitud no dependen de esa copia.

---

### Edge Cases

- La primera visita después de activar la vitrina no muestra fichas del modo anterior mezcladas con las del panel.
- Un cambio de tarifa interna que no toca el precio de vitrina no tiene por qué cambiar la ficha pública.
- Dos visitantes en la ventana de cinco minutos pueden ver, como máximo, el estado anterior. Pasada la ventana, ambos ven el estado nuevo.
- Guardar una copia no revela borradores ni datos de clientes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Un cambio de publicación, despublicación, agotado o precio de vitrina DEBE verse en una visita nueva en un máximo de cinco minutos.
- **FR-002**: Una ficha que dejó de ser pública DEBE desaparecer de visitas nuevas en ese mismo plazo, incluida su dirección directa.
- **FR-003**: Repetir una página pública ya abierta en la misma visita, sin un cambio de por medio, DEBE mostrarse sin repetir la espera de la primera apertura.
- **FR-004**: La copia usada para esa rapidez NO DEBE ser la fuente del precio final, de la disponibilidad confirmada ni del estado de una reserva.
- **FR-005**: La propuesta enviada al viajero DEBE conservar el precio con el que se emitió, aunque la vitrina cambie después.
- **FR-006**: Si se reutiliza una copia editorial porque el gestor no responde, el visitante DEBE notar que ese contenido puede no estar al día, o DEBE ver el aviso de contenido no disponible. Esa copia NO DEBE bloquear el catálogo ni la solicitud.
- **FR-007**: La copia pública NO DEBE incluir borradores, costos, notas internas ni datos de clientes.

### Key Entities

- **Vista pública reciente**: Lo que un visitante acaba de ver del catálogo o de una publicación. No es el expediente comercial.
- **Cambio publicable**: Publicar, despublicar, marcar agotado o corregir el precio de vitrina.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: En 10 cambios seguidos de publicar o despublicar, las 10 visitas nuevas hechas a los cinco minutos reflejan el cambio.
- **SC-002**: La segunda apertura de la misma ficha, en la misma visita y sin cambios, se completa en menos de 1 segundo en una conexión de banda ancha habitual.
- **SC-003**: En una prueba cruzada, el 100% de las propuestas abiertas por su enlace muestran su propio precio aunque la vitrina se haya modificado después.
- **SC-004**: Con el gestor editorial detenido, el 100% de los intentos de prueba siguen pudiendo abrir el catálogo y enviar una solicitud.

## Assumptions

- El catálogo (011), la solicitud (012) y el contenido editorial (013) ya están en el sitio público.
- Cinco minutos es el máximo aceptable para una visita nueva. La implementación puede ser más rápida.
- Las cotizaciones y las reservas conservan su propia copia comercial, como ya hacen 005 y 006.
- No se construye un almacén analítico ni se cachea la bandeja interna.
