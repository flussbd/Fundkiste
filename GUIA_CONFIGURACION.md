# Guía de configuración — Fundkiste

## Qué archivo es cada cosa

- **`index.html`** — página principal, pública, sin login (pero pide una clave de acceso compartida). Pide elegir la sede/colegio y muestra los artículos disponibles. Es la que compartes con padres y estudiantes.
- **`admin.html`** — app de gestión para el personal (requiere iniciar sesión). Desde aquí se registran artículos, se marcan retiros y se administran usuarios/sedes. Hay un link "Acceso para administradores" en `index.html` que lleva aquí.
- **`vitrina.html`** — ya no se usa directamente, solo redirige a `index.html` (por si alguien guardó ese link de una versión anterior).
- **`setup.sql`** — script que crea toda la base de datos en Supabase. No se sube a GitHub, solo se pega en el SQL Editor de Supabase.
- **`crear-usuario-edge-function.ts`** — código que se despliega en Supabase (no en GitHub) para poder crear cuentas de usuario desde `admin.html`.

Roles dentro de `admin.html`:

- **Administrador total**: ve y gestiona artículos de todas las sedes, y administra usuarios/sedes.
- **Administrador local**: ve y gestiona artículos solo de su propia sede.
- **Usuario (solo lectura)**: solo puede ver artículos. No puede registrar ni marcar retiros.

## Parte 1: Crear la base de datos en Supabase

1. Ve a [supabase.com](https://supabase.com) y crea una cuenta gratuita (puedes usar tu cuenta de Google).
2. Crea un nuevo proyecto: dale un nombre (ej. "fundkiste"), elige una contraseña de base de datos (guárdala) y una región cercana.
3. Espera a que el proyecto termine de crearse (1-2 minutos).
4. En el menú lateral, ve a **SQL Editor** → **New query**.
5. Abre el archivo `setup.sql`, copia todo su contenido, pégalo en el editor y presiona **Run**.
   - Esto crea las tablas `sedes`, `perfiles`, `articulos`, las funciones de rol, las funciones públicas (`articulos_publicos`, `sedes_publicas`) y todas las políticas de seguridad (RLS).
   - Si la parte del bucket de Storage falla, créalo manualmente: **Storage** → **New bucket** → nombre `fotos` → activa **Public bucket**.
6. Ve a **Authentication** → **Emails** → **Confirm sign up** (o **Sign In / Providers** → **Email**, según la versión del panel) y desactiva la confirmación por correo.
7. Ve a **Project Settings** → **API** (o **Data API** / botón **Connect**, según la versión) y copia:
   - **Project URL** (algo como `https://xxxxx.supabase.co`)
   - La clave **publishable** (`sb_publishable_...`) — nunca la **secret** (`sb_secret_...`), esa nunca debe ir en un archivo público.

## Parte 2: Crear el primer administrador total

1. Ve a **Authentication** → **Users** → **Add user**, y crea tu propia cuenta (correo + contraseña). Marca "Auto Confirm User" si aparece la opción.
2. Al crear el usuario, el sistema le asigna automáticamente el rol "viewer" sin sede. Para convertirte en administrador total, ve a **SQL Editor** y ejecuta (reemplazando el correo):

   ```sql
   update perfiles set rol = 'admin_total' where email = 'tu_correo@colegio.cl';
   ```

3. Con esa cuenta podrás iniciar sesión en `admin.html` y, desde el botón "👥 Usuarios", crear sedes y cuentas para el resto del personal.

## Parte 3: Pegar las credenciales en los archivos de la app

1. Abre `admin.html` con un editor de texto (Bloc de notas sirve). Busca:

   ```js
   const SUPABASE_URL = '...';
   const SUPABASE_ANON_KEY = '...';
   ```

   y reemplaza por el **Project URL** y la clave **publishable** de la Parte 1.
2. Haz lo mismo en `index.html` (tiene las mismas dos líneas).
3. Guarda ambos archivos.

Nota: la clave publishable está diseñada por Supabase para ir incluida en el código del frontend — no es secreta. La seguridad real (quién puede ver o editar qué) la dan las políticas RLS y las funciones configuradas por `setup.sql`.

## Parte 4: Publicar la app en GitHub Pages

1. Ve a [github.com](https://github.com) y crea una cuenta si no tienes una.
2. Crea un repositorio nuevo (ej. `fundkiste`), puede ser público o privado.
3. Sube `index.html`, `admin.html` y `vitrina.html` ya editados a ese repositorio (botón **Add file** → **Upload files**).
4. Ve a **Settings** → **Pages** (menú lateral del repositorio).
5. En **Branch**, selecciona `main` y carpeta `/ (root)`, luego **Save**.
6. Espera 1-2 minutos. GitHub te dará una URL tipo `https://tu-usuario.github.io/fundkiste/` — esa es la vitrina pública. La gestión queda en `https://tu-usuario.github.io/fundkiste/admin.html`.

## Parte 5: Crear sedes

1. Entra a `admin.html` con tu cuenta de administrador total.
2. Botón **👥 Usuarios** → pestaña **Sedes** → agrega cada sede del colegio (ej. "Sede Centro", "Sede Norte").

Estas mismas sedes aparecerán como botones para elegir en la página pública `index.html`.

## Parte 5b: Cambiar la clave de acceso a la vitrina pública

Al ejecutar `setup.sql` se crea una clave por defecto (`cambiar-esta-clave`) que hay que cambiar antes de compartir el link con las familias:

Tanto un administrador total como un administrador local pueden cambiarla:

1. Entra a `admin.html`.
2. Botón **👥 Usuarios** (admin total) o **🔑 Acceso público** (admin local).
3. Ahí ves la clave actual y puedes escribir una nueva → **Guardar nueva clave**.
4. Comparte esa clave con las familias por el medio que uses habitualmente (circular, agenda, etc.) junto con el link de `index.html`.

Importante: esto es una barrera simple para desalentar que cualquiera en internet entre a curiosear, **no es una protección técnica real** — como la app es un archivo estático, alguien con conocimientos técnicos podría revisar el código o llamar directo a la función de verificación. No la uses pensando que protege datos realmente sensibles; para eso existen los roles con login real de `admin.html`.

Nota: hay **una sola clave compartida** para todas las sedes (no una por sede). Si un administrador local la cambia, afecta el acceso a la vitrina de todas las sedes, no solo la suya.

## Parte 6: Activar la creación de usuarios desde la app (opcional pero recomendado)

Por defecto, crear cuentas nuevas requiere entrar manualmente a Supabase (**Authentication → Users → Add user**). Si quieres poder crear cuentas directamente desde el panel "👥 Usuarios" de `admin.html`, despliega una función que vive en Supabase (nunca en un archivo público) y que es la única con permiso para crear cuentas de forma segura.

1. En el dashboard de Supabase, ve a **Edge Functions** (menú lateral).
2. Clic en **Deploy a new function** → **Via Editor**.
3. Nombra la función exactamente: `crear-usuario`.
4. Borra el código de ejemplo y pega todo el contenido de `crear-usuario-edge-function.ts`.
5. Clic en **Deploy**.
6. No necesitas configurar ninguna clave manualmente: Supabase le da automáticamente a la función acceso seguro a tu proyecto.

Una vez desplegada, en `admin.html` → botón **👥 Usuarios** aparece arriba un formulario **"Crear cuenta nueva"**. Solo un administrador total puede usarlo (la función lo verifica del lado del servidor, no solo en la pantalla).

Si al crear un usuario aparece un error mencionando la función, revisa que el nombre sea exactamente `crear-usuario` y que se haya desplegado sin errores (la pantalla de Edge Functions muestra el estado/logs).

## Parte 7: Agregar al resto del personal

Con la función desplegada, para cada persona nueva:

1. En `admin.html`, botón **👥 Usuarios** → completa "Crear cuenta nueva" (correo, contraseña, nombre, rol y sede si corresponde) → **Crear cuenta**.
2. Avísale su correo y contraseña.

Si no desplegaste la función (Parte 6), puedes seguir creando cuentas manualmente en Supabase y asignarles el rol desde la lista "Usuarios existentes" en el mismo panel.

## ¿Cómo se usa?

**`index.html` (público, sin login):**
- Al entrar, primero pide elegir la sede/colegio — la recuerda para la próxima visita (hay un botón "Cambiar sede" en el encabezado).
- Luego pide la clave de acceso (la recuerda en el navegador mientras siga siendo la misma clave). Si el administrador cambia la clave, la próxima vez que cualquier persona entre —incluso si ya la había puesto antes en ese mismo navegador— se le vuelve a pedir la clave nueva. Requiere haber ejecutado la versión más reciente de `setup.sql`.
- Muestra los artículos disponibles de esa sede: foto, tipo, color, talla, si tiene nombre, lugar y fecha en que se encontró.
- No muestra artículos ya retirados, ni quién los registró o retiró.
- No permite registrar ni retirar artículos — solo consultar.

**`admin.html` (personal con cuenta):**
- **Registrar un artículo**: botón `+` (solo administradores). Foto opcional, categoría, tipo, color, talla, si tiene nombre bordado, lugar y fecha. Un administrador local registra directo en su sede; un administrador total elige la sede.
- **Buscar/filtrar**: búsqueda por texto, filtro por categoría, filtro por sede (si el usuario ve más de una), pestañas Disponibles / Retirados / Todos.
- **Marcar como retirado**: en el detalle de un artículo disponible, los administradores registran nombre, curso y fecha de quien lo retira. Los usuarios de solo lectura ven el detalle pero no este formulario.
- **Eliminar un artículo**: en el detalle de cualquier artículo, botón "Eliminar artículo" (pide confirmación). Un administrador total puede eliminar de cualquier sede; un administrador local solo de su propia sede. Los usuarios de solo lectura no ven este botón. Si ya tenías la base de datos creada de antes, debes volver a ejecutar `setup.sql` para que el administrador local quede habilitado para eliminar (antes solo lo permitía admin_total).
- **Mi cuenta**: cualquier usuario logueado (sin importar su rol) puede cambiar su propio nombre y su contraseña desde el botón "⚙ Mi cuenta" en el encabezado. No puede cambiar su propio rol ni sede desde ahí — eso lo sigue controlando solo el administrador total (o local, para la clave de acceso pública).

## Notas importantes

- No estoy seguro de los límites exactos del plan gratuito de Supabase en este momento (pueden cambiar); conviene revisar la [documentación oficial de precios](https://supabase.com/pricing) si el colegio espera un volumen alto de fotos o registros.
- La clave de administrador que permite crear cuentas nunca queda en los archivos públicos — vive solo dentro de la función `crear-usuario` en Supabase.
- Si alguien olvida su contraseña, se puede restablecer desde **Authentication** → **Users** en Supabase.
