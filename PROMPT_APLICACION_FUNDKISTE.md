# Fundkiste — especificación completa de la aplicación

Este documento describe, de punta a punta, la aplicación "Fundkiste" tal como está construida hoy, para que sirva como prompt/spec si se quiere reconstruir, auditar o extender con otra herramienta (o con Claude en una sesión nueva). Al final se listan las mejoras recomendadas, priorizadas.

## 1. Contexto y objetivo

Fundkiste es el sistema de objetos perdidos del Colegio Alemán Chicureo. Reemplaza un registro en Google Docs (donde no se podía ver la ropa/artículo perdido) por una aplicación web donde el personal registra artículos con foto y detalles, y las familias pueden revisar en línea si algo suyo aparece, sin necesidad de cuenta.

Requisitos originales: tomar una foto, registrar categoría, tipo, color, talla, si tiene nombre bordado, lugar y fecha en que se encontró, y registrar quién y cuándo lo retiró.

## 2. Arquitectura técnica

- **Frontend**: archivos HTML estáticos independientes (sin build step, sin framework), cada uno con su propio `<style>` y `<script>` inline. Publicados vía **GitHub Pages** desde la rama `main`.
- **Backend**: **Supabase** (Postgres + Auth + Storage + Edge Functions), usando el SDK `@supabase/supabase-js@2` cargado desde CDN (`https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2`).
- **Claves**: se usa la clave **publishable** (`sb_publishable_...`) en el frontend — es pública por diseño. La clave **secret** (`sb_secret_...` / service role) nunca aparece en ningún archivo público; solo vive como variable de entorno auto-inyectada dentro de la Edge Function.
- **Seguridad real**: se implementa con **Row Level Security (RLS)** de Postgres, no con lógica de interfaz. Toda regla de "quién puede ver/crear/editar/borrar qué" está en políticas SQL, verificables independientemente del frontend.
- **Tipografías**: Google Fonts — Fraunces (display serif, títulos), Inter (texto), IBM Plex Mono (datos, fechas, cifras).
- **Identidad visual**: paleta "papel/musgo/sello/latón" (ver sección 7), motivo de "caja de cosas perdidas" con un ícono SVG propio de cajón con etiqueta colgante, en vez de emojis o clip-art genérico.

### Archivos del repositorio

| Archivo | Rol |
|---|---|
| `index.html` | Vitrina pública, sin login, con clave de acceso compartida |
| `admin.html` | App de gestión para el personal (login real) |
| `dashboard.html` | Panel de estadísticas, solo admin_total/admin_local |
| `vitrina.html` | Redirect stub a `index.html` (compatibilidad con links viejos) |
| `setup.sql` | Script único que crea/actualiza todo el esquema en Supabase (idempotente, se puede re-ejecutar) |
| `crear-usuario-edge-function.ts` | Código de la Edge Function `crear-usuario` (se despliega en Supabase, no en GitHub) |
| `GUIA_CONFIGURACION.md` | Guía paso a paso de instalación/uso para una persona no técnica |

## 3. Modelo de datos (Postgres / Supabase)

**`sedes`** — sucursales del colegio.
`id uuid PK`, `nombre text unique not null`, `created_at`.

**`perfiles`** — un registro por usuario de `auth.users`, con su rol y sede.
`id uuid PK (= auth.users.id)`, `email`, `nombre`, `rol text check in ('admin_total','admin_local','viewer') default 'viewer'`, `sede_id uuid → sedes`, `created_at`.
Se crea automáticamente vía trigger `on_auth_user_created` → `handle_new_user()` cuando alguien se crea en Supabase Auth (rol `viewer` por defecto, sin sede).

**`puntos`** — lugares de acopio dentro de una sede (ej. "Portería", "Gimnasio"). Puramente informativo, no restringe categorías.
`id uuid PK`, `sede_id uuid → sedes not null`, `nombre text not null`, `unique(sede_id, nombre)`, `created_at`.

**`admin_puntos_permitidos`** — restricción opcional: a qué puntos queda limitado un administrador local para crear/editar/eliminar artículos. Sin filas para un usuario = sin restricción (puede gestionar todos los puntos de su sede).
`perfil_id uuid → perfiles`, `punto_id uuid → puntos`, `PK (perfil_id, punto_id)`.

**`articulos`** — el objeto perdido.
`id uuid PK`, `sede_id uuid → sedes not null`, `punto_id uuid → puntos (on delete set null)`, `categoria text not null` ('Ropa' | 'Útiles escolares' | 'Otro'), `tipo text not null`, `color`, `talla`, `tiene_nombre boolean default false`, `nombre_bordado`, `descripcion`, `foto_url` (URL pública en Storage), `lugar_encontrado`, `fecha_encontrado date not null`, `registrado_por text not null`, `estado text default 'disponible'` ('disponible' | 'retirado'), `retirado_por`, `curso_retiro`, `fecha_retiro date`, `modificado_por text`, `modificado_en timestamptz`, `created_at`.
Índices en `estado`, `categoria`, `sede_id`, `punto_id`, `fecha_encontrado desc`.

**`configuracion`** — fila única (`id=1`) con la clave de acceso compartida de la vitrina pública.
`clave_acceso text not null default 'cambiar-esta-clave'`, `clave_actualizada timestamptz` (se actualiza sola vía trigger `touch_clave_actualizada` cada vez que cambia `clave_acceso`, para poder detectar el cambio desde el navegador).

**Storage**: bucket público `fotos`. Lectura pública para cualquiera; subida (`insert`) solo para `admin_total`/`admin_local`.

### Funciones de seguridad (security definer)

- `get_my_role()`, `get_my_sede()` — evitan recursión de RLS al consultar el propio perfil.
- `punto_permitido(punto_id)` — true si el usuario no tiene restricciones, si el artículo no tiene punto, o si el punto está en su lista permitida.
- `articulos_publicos()` — para la vitrina pública (`anon`): solo artículos `disponible`, sin columnas sensibles (excluye `registrado_por`, `retirado_por`, `curso_retiro`, `fecha_retiro`).
- `sedes_publicas()` — lista pública de `id, nombre` de sedes.
- `verificar_clave_publica(intento)` — compara sin exponer la clave real; devuelve solo `boolean`.
- `clave_estado_publica()` — expone solo la fecha de última actualización de la clave (nunca la clave), para que el navegador detecte que cambió.
- `actualizar_mi_nombre(nuevo_nombre)` — autoedición de nombre propio, no puede tocar rol ni sede.

## 4. Roles y permisos

| Acción | admin_total | admin_local | viewer |
|---|---|---|---|
| Ver artículos | Todas las sedes | Solo su sede | Su sede, o todas si no tiene sede asignada |
| Crear artículo | Cualquier sede | Solo su sede (y sus puntos permitidos, si están configurados) | No |
| Editar información de artículo | — (no tiene el botón, ver nota) | Sí, su sede + puntos permitidos | No |
| Marcar retiro | Sí | Sí, su sede | No |
| Eliminar artículo | Cualquier sede | Sí, su sede + puntos permitidos | No |
| Gestionar usuarios/sedes | Sí | No | No |
| Gestionar puntos de acopio | Sí (elige sede) | Sí, solo su sede | No |
| Cambiar clave de acceso pública | Sí | Sí | No |
| Asignar puntos permitidos a un admin_local | Sí | No | No |
| Dashboard | Sí (todas las sedes + comparación) | Sí (solo su sede) | No |
| Mi cuenta (nombre/contraseña propios) | Sí | Sí | Sí |

Nota de diseño explícita: el botón "Editar información" de un artículo se decidió, a pedido, que **solo lo vea admin_local**, no admin_total (admin_total sí puede eliminar y ver todo, pero no tiene ese botón).

## 5. Páginas y funcionalidades

### `index.html` — vitrina pública (sin login)

Flujo: **1) elegir sede** (botones, recordado en `localStorage` como `fk_sede_elegida`) → **2) clave de acceso** compartida (recordada como `fk_clave_ok` + versión `fk_clave_version`; si el admin cambia la clave, se detecta por `clave_estado_publica()` y se vuelve a pedir aunque ya estuviera "recordada") → **3) grilla de artículos disponibles** de esa sede, con foto, categoría, tipo, color, talla, lugar y fecha. Filtro de búsqueda y por categoría. Vista de detalle en overlay. Botón "Cambiar sede". No muestra artículos retirados ni datos de quién retiró/registró.

### `admin.html` — gestión (login con correo/contraseña)

- Login con `sb.auth.signInWithPassword`.
- Grilla de artículos con búsqueda, filtro por categoría y sede (si aplica), pestañas Disponibles/Retirados/Todos.
- **Registrar artículo** (botón flotante `+`): foto (comprimida antes de subir, ver más abajo), sede (fija si es admin_local), punto de acopio (**obligatorio si la sede ya tiene puntos creados**, opcional si aún no tiene ninguno), categoría, tipo, color, talla, nombre bordado, lugar, fecha, descripción.
- **Compresión de fotos**: al elegir/tomar una foto, se redibuja en un `<canvas>` limitando el lado mayor a 1600px y se exporta como JPEG calidad 0.75, mostrando el peso resultante ("Peso de la foto: X KB/MB").
- **Detalle de artículo**: datos completos + "Registrado por" + "Última modificación" (quién y cuándo, si se editó o se marcó retiro alguna vez). Botón "Marcar como retirado" (nombre, curso, fecha de quien retira). Botón "Editar información" (solo admin_local, solo si el punto del artículo está entre sus puntos permitidos). Botón "Eliminar artículo" (admin_total y admin_local, con confirmación).
- **Panel de administración** (pestañas):
  - *Usuarios* (solo admin_total): crear cuenta nueva (vía Edge Function `crear-usuario`), lista de usuarios existentes editable (nombre, rol, sede), y por cada admin_local con puntos en su sede, checklist de "puntos permitidos".
  - *Sedes* (solo admin_total): crear sedes.
  - *Puntos*: admin_total elige sede y gestiona sus puntos; admin_local ve directo los de su sede. Agregar/eliminar puntos.
  - *Acceso público* (admin_total y admin_local): ver/cambiar la clave de acceso de la vitrina.
- **Mi cuenta** (cualquier rol logueado): cambiar nombre propio (`actualizar_mi_nombre`) y contraseña (`sb.auth.updateUser`).
- Botón "📊 Dashboard" (admin_total/admin_local) hacia `dashboard.html`.

### `dashboard.html` — estadísticas (solo admin_total/admin_local)

Página separada, con su propio login (o sesión heredada si ya se inició sesión en `admin.html`, mismo origen). Muestra: KPIs (total, disponibles, retirados, % retirado), desglose por categoría, desglose por punto de acopio, tendencia de artículos registrados en los últimos 6 meses (por `fecha_encontrado`), y artículos disponibles hace más de 30 días sin retirar. admin_total ve, por defecto, todas las sedes agregadas + tabla comparativa entre sedes; puede filtrar a una sede específica (ahí se reemplaza la comparación por el desglose de puntos de esa sede). admin_local ve directo los datos de su sede, sin selector.

### `vitrina.html`

Solo contiene un `<meta http-equiv="refresh">` hacia `index.html`, por compatibilidad con links guardados de una versión anterior donde este era el nombre de la página pública.

## 6. Seguridad — decisiones explícitas

- La clave `sb_secret_...` (service role) **nunca** va en un archivo del repositorio; solo existe como variable de entorno auto-inyectada dentro de la Edge Function `crear-usuario`, que la usa para crear cuentas después de verificar server-side (con el JWT de quien llama) que el solicitante es `admin_total`.
- Toda regla de permisos está en RLS de Postgres, no solo escondida en la interfaz — se puede verificar independientemente del código del frontend.
- La vitrina pública excluye deliberadamente cualquier dato de quién retiró o registró un artículo, y no lista artículos ya retirados.
- La "clave de acceso" de la vitrina es, por diseño y documentado explícitamente, una barrera **no criptográfica** contra visitas casuales — no protege datos realmente sensibles, y no tiene límite de intentos.
- Texto libre ingresado por usuarios se escapa (`escapeHtml`) antes de insertarse como HTML, salvo `foto_url`, cuyo nombre de archivo se sanea a alfanumérico + punto antes de subir, evitando inyección en atributos.

## 7. Sistema de diseño

**Paleta** (tokens CSS en `:root`): `--bg #F6F1E4` (papel), `--panel #FFFEFA`, `--ink #1F2A24`, `--ink-soft #6B7A6E`, `--line #E4DCC4`, `--accent #5B6B4F` (musgo), `--accent-dark #3F4A38`, `--ok #4C7A4E`, `--warn #B23A2E`, `--info #4A6FA5`, `--brass #B08D57` (latón/sello).

**Tipografía**: Fraunces (títulos/`h1`/`h2`), Inter (cuerpo, UI), IBM Plex Mono (fechas, cifras, badges de categoría).

**Signature/ícono**: SVG propio de un cajón de madera con una etiqueta colgante amarrada con hilo (reemplaza cualquier emoji o ícono genérico), usado en el header y login de las tres páginas.

**Motivo**: "caja de cosas perdidas" — evita deliberadamente la paleta "crema cálido + terracota" por defecto de diseños generados por IA.

## 8. Convención de versionado

Un único número de versión (`vX.Y`, ej. `v1.8`) se muestra en el pie de página de **las tres páginas a la vez** (`index.html`, `admin.html`, `dashboard.html`) y se sube en conjunto con cada cambio, aunque solo se haya modificado un archivo — así el usuario puede confirmar de un vistazo que todas las páginas están sincronizadas tras un despliegue.

## 9. Mejoras recomendadas (priorizadas)

1. **Rediseño visual del dashboard**: hoy usa tarjetas KPI y barras genéricas (el "look de dashboard por defecto"). Debería adoptar la misma identidad "manifiesto de inventario/bodega" del resto de la app: cifras en monospace con líneas punteadas tipo ficha de inventario en vez de barras de progreso planas, el sello de latón para destacar el % retirado, y reemplazar los emojis sueltos (🎉) por íconos propios de la familia del cajón.
2. **Soporte para más de una foto por artículo**: hoy es una sola `foto_url`; requeriría una tabla de fotos aparte o un array de URLs.
3. **Pruebas automatizadas**: hoy la validación es manual (chequeo de sintaxis JS y balance de HTML tras cada cambio); no hay tests de RLS ni de UI. Con el volumen de reglas de permisos ya acumuladas (rol × sede × punto), un set de pruebas de RLS directamente en SQL evitaría regresiones silenciosas.
4. **Ambiente de prueba separado**: todo cambio se prueba directo en producción (mismo proyecto Supabase, mismo repo). Un proyecto Supabase de staging (o al menos una rama de prueba) evitaría que un error de SQL afecte a los usuarios reales mientras se prueba.
5. **Automatizar el despliegue**: hoy el flujo depende de que el usuario ejecute manualmente `setup.sql` en el SQL Editor cada vez que cambia el esquema, y de recordar hacer `git push`. Esto ya causó confusión repetida (versiones desincronizadas, caché de navegador, olvidos de re-ejecutar el SQL). Migrar a Supabase CLI + migraciones versionadas (o al menos un checklist/script de despliegue) reduciría el margen de error humano.
6. **Límite de intentos en la clave de acceso pública**: está documentado como no-crítico, pero un límite simple (ej. bloquear tras varios intentos fallidos seguidos) sería una mejora barata si en algún momento preocupa el uso indebido.
7. **Paginación / carga incremental** en las grillas de artículos: hoy se trae todo con `select('*')` sin límite; no es un problema al volumen actual, pero conviene tenerlo presente si el historial crece por varios años sin depurarse.
8. **Backups / plan de recuperación**: no hay un procedimiento documentado de respaldo de la base de datos más allá de lo que Supabase ofrece por defecto en el plan gratuito.
