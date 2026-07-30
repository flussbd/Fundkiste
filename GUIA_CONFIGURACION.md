# Guía de configuración — Fundkiste

La app tiene tres roles:

- **Administrador total**: ve y gestiona artículos de todas las sedes, y administra usuarios/sedes.
- **Administrador local**: ve y gestiona artículos solo de su propia sede.
- **Usuario (solo lectura)**: solo puede ver artículos (de su sede, o de todas si no tiene sede asignada). No puede registrar ni marcar retiros.

## Parte 1: Crear la base de datos en Supabase

1. Ve a [supabase.com](https://supabase.com) y crea una cuenta gratuita (puedes usar tu cuenta de Google).
2. Crea un nuevo proyecto: dale un nombre (ej. "fundkiste"), elige una contraseña de base de datos (guárdala) y una región cercana.
3. Espera a que el proyecto termine de crearse (1-2 minutos).
4. En el menú lateral, ve a **SQL Editor** → **New query**.
5. Abre el archivo `setup.sql` (incluido junto a esta guía), copia todo su contenido, pégalo en el editor y presiona **Run**.
   - Esto crea las tablas `sedes`, `perfiles`, `articulos`, las funciones de rol y todas las políticas de seguridad (RLS).
   - Si la parte del bucket de Storage falla, créalo manualmente: **Storage** → **New bucket** → nombre `fotos` → activa **Public bucket**.
6. Ve a **Authentication** → **Providers** → **Email**, y desactiva "Confirm email" (así no necesitas que cada usuario confirme su correo; como tú creas las cuentas manualmente, no hace falta).
7. Ve a **Project Settings** → **API** y copia:
   - **Project URL** (algo como `https://xxxxx.supabase.co`)
   - **anon public key** (una clave larga que empieza con `eyJ...`)

## Parte 2: Crear el primer administrador total

1. Ve a **Authentication** → **Users** → **Add user**, y crea tu propia cuenta (correo + contraseña). Marca "Auto Confirm User" si aparece la opción.
2. Al crear el usuario, el sistema le asigna automáticamente el rol "viewer" sin sede. Para convertirte en administrador total, ve a **SQL Editor** y ejecuta (reemplazando el correo):

   ```sql
   update perfiles set rol = 'admin_total' where email = 'tu_correo@colegio.cl';
   ```

3. Con esa cuenta podrás iniciar sesión en la app y, desde el botón "👥 Usuarios", crear sedes y asignar roles al resto del personal (una vez que tú u otro administrador cree sus cuentas en el paso siguiente).

## Parte 3: Pegar las credenciales en el archivo de la app

1. Abre `index.html` con un editor de texto (Bloc de notas sirve).
2. Busca estas dos líneas cerca del final del archivo:

   ```js
   const SUPABASE_URL = 'PON_TU_SUPABASE_URL_AQUI';
   const SUPABASE_ANON_KEY = 'PON_TU_SUPABASE_ANON_KEY_AQUI';
   ```

3. Reemplaza los textos entre comillas por el **Project URL** y el **anon public key** que copiaste en la Parte 1, paso 7.
4. Guarda el archivo.

Nota: el "anon key" está diseñado por Supabase para ir incluido en el código del frontend — no es secreto. La seguridad real (quién puede ver o editar qué) la dan las políticas RLS que ya quedaron configuradas por `setup.sql`.

## Parte 4: Publicar la app en GitHub Pages

1. Ve a [github.com](https://github.com) y crea una cuenta si no tienes una.
2. Crea un repositorio nuevo (ej. `fundkiste-colegio`), puede ser público o privado.
3. Sube el archivo `index.html` ya editado (con tus credenciales) a ese repositorio (botón **Add file** → **Upload files**).
4. Ve a **Settings** → **Pages** (menú lateral del repositorio).
5. En **Branch**, selecciona `main` y carpeta `/ (root)`, luego **Save**.
6. Espera 1-2 minutos. GitHub te dará una URL tipo `https://tu-usuario.github.io/fundkiste-colegio/` — esa es la dirección de la app.

## Parte 5: Crear sedes y agregar al resto del personal

1. Entra a la app con tu cuenta de administrador total.
2. Botón **👥 Usuarios** → pestaña **Sedes** → agrega cada sede del colegio (ej. "Sede Centro", "Sede Norte").
3. Para cada persona nueva: créala en Supabase (**Authentication** → **Users** → **Add user**, marcando "Auto Confirm User"). Avísale su correo y contraseña.
4. En la app, botón **👥 Usuarios** → pestaña **Usuarios** → **🔄 Recargar lista** → busca su correo, asígnale el rol (Admin local / Admin total / Solo lectura) y, si corresponde, su sede → **Guardar**.

## ¿Cómo se usa?

- **Registrar un artículo**: botón `+` abajo a la derecha (solo visible para administradores). Se puede tomar foto con la cámara o subir una desde la galería, y llenar categoría, tipo, color, talla, si tiene nombre bordado, dónde se encontró y la fecha. Un administrador local registra directo en su sede; un administrador total elige la sede.
- **Buscar/filtrar**: barra de búsqueda por texto, filtro por categoría, filtro por sede (si el usuario puede ver más de una), y pestañas de Disponibles / Retirados / Todos.
- **Marcar como retirado**: al hacer clic en un artículo disponible, los administradores pueden registrar el nombre de quien lo retira, su curso y la fecha. Los usuarios de solo lectura ven el detalle pero no este formulario.

## Notas importantes

- No estoy seguro de los límites exactos del plan gratuito de Supabase en este momento (pueden cambiar); conviene revisar la [documentación oficial de precios](https://supabase.com/pricing) si el colegio espera un volumen alto de fotos o registros.
- Crear cuentas nuevas (correo/contraseña) solo se puede hacer desde el panel de Supabase, no desde la app — esto es intencional, por seguridad (crear cuentas requiere una clave de administrador que nunca debe quedar en un archivo público como este).
- Si alguien olvida su contraseña, se puede restablecer desde **Authentication** → **Users** en Supabase.
