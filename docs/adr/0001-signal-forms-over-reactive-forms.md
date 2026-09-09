# ADR-0001: Adopción de Signal Forms sobre Reactive Forms

- **Identifier**: ADR-0001
- **Title**: Adopción de Signal Forms como estrategia oficial de formularios en el frontend
- **Status**: Accepted
- **Date**: 2026-09-08
- **Deciders**: Equipo de Arquitectura
- **Affected Chapters**: Cap. 1 (Technology Direction), Cap. 14 (Approved Technology Strategy)

## Context

La constitución establecía originalmente **Reactive Forms** como el mecanismo aprobado
para la gestión de formularios en el frontend Angular. Al actualizar la dirección
tecnológica a la última versión estable de **Angular 22** (junio 2026), **Signal Forms**
alcanzó estabilidad como API de formularios integrada de forma nativa con Angular Signals,
que ya es la base reactiva oficial del proyecto (`Angular Signals`, `computed()`,
componentes standalone por defecto).

Mantener Reactive Forms junto a un stack basado en Signals introducía dos modelos de
reactividad paralelos (Observables/`FormControl` vs. Signals), aumentando la carga
cognitiva y la inconsistencia entre la gestión de estado de autenticación (Signals) y la
gestión de formularios (Reactive Forms).

Esta es una decisión de nivel arquitectónico (Level 3) según el Cap. 3 de la constitución,
por lo que requiere un ADR.

## Decision

El proyecto adopta **Signal Forms** como la estrategia oficial y por defecto para todos los
formularios del frontend, reemplazando a **Reactive Forms** en la dirección tecnológica
aprobada.

- Cap. 1 (Technology Direction): `Reactive Forms` → `Signal Forms`.
- Cap. 14 (Official Technology Stack): `Reactive Forms` → `Signal Forms`.

Los planes de implementación existentes (`specs/001-auth-tenant-access/plan.md`) ya
referencian Signal Forms y quedan alineados con esta decisión.

## Alternatives considered

- **Mantener Reactive Forms**: Descartado. Introduce dos modelos de reactividad paralelos
  (Observables + Signals), contraviniendo los principios de *Simplicity Over Complexity* y
  *Consistency* de la constitución.
- **Template-driven Forms**: Descartado. Menor control sobre validación compleja y peor
  encaje con una arquitectura basada en Signals y validación explícita.
- **Coexistencia Reactive + Signal Forms**: Descartado para el MVP. Fragmenta convenciones
  y viola *Convention Over Configuration*; la coexistencia solo se contemplaría mediante un
  nuevo ADR si surge una necesidad de negocio medible.

## Consequences

**Positivas**
- Un único modelo reactivo (Signals) para estado de aplicación y formularios.
- Menor carga cognitiva y mayor consistencia arquitectónica.
- Alineación con la dirección oficial y estable de Angular 22.

**Negativas / Riesgos**
- Signal Forms es una API relativamente nueva; menor volumen de recursos/comunidad frente a
  Reactive Forms.
- El equipo debe adoptar el nuevo patrón; se requiere actualizar Development Standards y
  ejemplos de referencia.

**Seguimiento**
- Actualizar los Development Standards con convenciones de Signal Forms (validadores,
  manejo de errores, formularios anidados).
- Cualquier reversión o coexistencia con Reactive Forms requerirá un nuevo ADR.
