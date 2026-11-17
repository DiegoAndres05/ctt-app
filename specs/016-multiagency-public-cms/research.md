# Research: Base multiagencia del contenido público

## Decisión 1: Extender el modelo público existente

- **Decisión**: Reutilizar `public_sites`, `public_categories`, `public_listings`,
  `public_images`, `guest_reviews`, `public_cutover_items` y `get_public_site`,
  agregando configuración propia de agencia.
- **Racional**: El feature 009 ya garantiza compatibilidad con los identificadores,
  imágenes, publicación y cutover que CTT utiliza. Crear un segundo modelo duplicaría
  reglas y aumentaría el riesgo de romper direcciones públicas.
- **Alternativas consideradas**: Crear un CMS paralelo o reemplazar las tablas
  existentes. Se descartan por duplicación y por el requisito de transición sin cortes.

## Decisión 2: Credencial pública opaca y limitada

- **Decisión**: Generar una credencial aleatoria no derivable del identificador de
  organización, persistir únicamente su huella y exponerla solo al Administrador.
  La credencial autoriza lectura del perfil/catálogo publicado y envío de solicitudes,
  nunca acceso al panel ni a datos internos.
- **Racional**: Reduce el impacto de una filtración y evita que una clave pública se
  convierta en un identificador enumerables de agencias. Las respuestas de credenciales
  ausentes, revocadas o vencidas deben ser genéricas.
- **Alternativas consideradas**: Usar directamente el UUID de la organización o una
  clave almacenada en texto plano. Se descartan porque facilitan enumeración y amplían
  el impacto de una exposición.

## Decisión 3: Rotación con ventana fija de 7 días

- **Decisión**: Al regenerar, la clave anterior permanece válida exactamente 7 días;
  la fecha de expiración se informa al Administrador. La revocación invalida de
  inmediato todas las credenciales asociadas.
- **Racional**: Cumple la aclaración del spec y permite actualizar una vitrina sin
  corte inmediato, manteniendo una ventana limitada.
- **Alternativas consideradas**: Revocación inmediata, 24 horas y 30 días. La primera
  rompe migraciones; 30 días prolonga innecesariamente la exposición.

## Decisión 4: Autorización en PostgreSQL

- **Decisión**: Mantener las comprobaciones de rol, agencia, estado de clave y
  publicación en RPCs `SECURITY DEFINER` con `search_path` restringido, RLS para
  operaciones autenticadas y pruebas SQL de aislamiento.
- **Racional**: Es el patrón existente para publicaciones y operaciones sensibles, y
  evita confiar en validaciones del cliente.
- **Alternativas consideradas**: Aplicar permisos solo en Angular o resolver acceso
  público desde un servicio intermedio. Se descartan porque no protegen llamadas
  directas al backend.

## Decisión 5: Configuración inicial idempotente por agencia

- **Decisión**: Crear los valores de ejemplo y el perfil base al crear una agencia,
  con identificadores estables y posibilidad de desactivar. Los valores CTT se
  conservan mediante una migración/backfill que no renombra registros existentes.
- **Racional**: Hace determinista el onboarding y preserva los filtros actuales.
- **Alternativas consideradas**: Un catálogo global compartido o sembrar valores solo
  cuando se abre la pantalla. Se descartan por riesgo de fuga entre agencias y estados
  incompletos.

## Decisión 6: Contratos públicos con proyección mínima

- **Decisión**: La interfaz pública devuelve perfil y catálogo publicado en una
  proyección explícita; no devuelve tablas internas, usuarios, clientes, costos,
  prestadores ni tarifas operativas.
- **Racional**: Mantiene una frontera clara de privacidad y permite evolucionar el
  almacenamiento interno sin romper vitrinas.
- **Alternativas consideradas**: Exponer filas completas de `public_listings` o
  aceptar cualquier campo solicitado por el consumidor. Se descartan por filtración
  de datos y acoplamiento.

