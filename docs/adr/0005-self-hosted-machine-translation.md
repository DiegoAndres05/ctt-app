# ADR-0005: Traducción automática del blog con LibreTranslate alojado por el proyecto

- **Identifier**: ADR-0005
- **Title**: Servicio de traducción automática de código abierto, propio, para borradores del blog
- **Status**: Accepted · implementado (migración `072`, función `translate-blog`, editor)
- **Date**: 2026-11-17 (propuesto y aceptado)
- **Deciders**: Responsable del proyecto (dueño de la Constitución)
- **Change level**: Nivel 3, servicio de infraestructura nuevo (Constitución, *Change Approval Levels*)
- **Affected Chapters**: Constitución, *Technology Direction → Infrastructure*.
- **Affected Specs**: `specs/017-blog-translation/` (nuevo); usa `specs/013-editorial-content/` sin cambiarlo.

## Context

Las agencias que ofrecen español e inglés deben escribir cada artículo dos veces: 013 exige cada idioma completo para publicar. El responsable pidió traducir automáticamente un idioma al otro, dejando el resultado editable, con dos condiciones: que sea **gratis** y **sin IA** (sin modelos generativos tipo ChatGPT o Claude).

Todo traductor automático actual usa redes neuronales. Se aceptó que la condición excluye la IA generativa y los servicios de pago o de terceros, no la traducción automática neuronal clásica.

## Decision

1. Se usa **LibreTranslate** (AGPL-3.0, motor Argos Translate), en un contenedor Docker propio con solo los modelos español↔inglés.
2. El navegador nunca llama al traductor. Una Edge Function autenticada (`translate-blog`) comprueba el rol y un límite de 150.000 caracteres por agencia y hora mediante una RPC, y reenvía el texto. El panel envía los artículos largos en partes de hasta 5.000 caracteres, porque el traductor tarda unos 2 s por frase en una CPU modesta. La dirección del servidor es un secreto (`LIBRETRANSLATE_URL`).
3. La traducción solo rellena el editor como borrador; nunca guarda ni publica. La revisión humana y la validación de 013 siguen siendo obligatorias.
4. El alojamiento de producción queda **por decidir**. Mientras no exista, la función responde «no disponible» y el panel funciona igual que hoy.

**Enmienda propuesta** a *Technology Direction → Infrastructure*:

```
- Self-hosted open-source machine translation (LibreTranslate) for editorial drafts
```

## Consequences

- **Positivas**: coste por uso cero; el texto no sale de la infraestructura propia; si el traductor falla, el blog no se ve afectado.
- **Negativas**: un servicio más que operar (~2 GB de RAM, ~1 GB de disco); calidad inferior a servicios comerciales, sobre todo en nombres propios; licencia AGPL (se usa como servicio sin modificar, sin obligación de publicar el código del panel).
- **Neutrales**: el uso se limita por agencia; no se audita la traducción porque guardar y publicar ya se auditan.

## Alternatives considered

| Alternativa | Por qué no |
| --- | --- |
| DeepL API Free | Mejor calidad, pero tope de 500.000 caracteres al mes, cuenta y clave, y el texto sale a un tercero. |
| Google / Azure Translator | De pago por volumen y externos. |
| MyMemory | Gratuito pero con tope diario bajo y externo. |
| IA generativa (Claude, GPT) | Excluida por el responsable. |
| Traducción en el navegador (Bergamot) | Sin servidor, pero descarga ~30 MB de modelos en cada equipo y sin paquete mantenido para Angular. Queda como opción futura. |
| No traducir (solo ayuda manual) | No resuelve la petición. |

## Checklist

- [x] ADR aceptado por el responsable (2026-11-17).
- [x] Enmienda aplicada a la Constitución (*Technology Direction → Infrastructure*).
- [x] Spec 017 implementado (migración 072, `translate-blog`, editor).
- [ ] Alojamiento de producción decidido y `LIBRETRANSLATE_URL` configurado.
