-- =========================================================
-- Fundkiste - Esquema de base de datos para Supabase
-- =========================================================
-- Ejecuta este script completo en: Supabase > SQL Editor > New query
-- Se puede correr varias veces sin duplicar datos (usa IF NOT EXISTS).
-- =========================================================

-- ---------------------------------------------------------
-- 1. Sedes (sucursales del colegio)
-- ---------------------------------------------------------
create table if not exists sedes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- 2. Perfiles (rol y sede de cada usuario que inicia sesión)
-- ---------------------------------------------------------
create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nombre text,
  rol text not null default 'viewer' check (rol in ('admin_total','admin_local','viewer')),
  sede_id uuid references sedes(id),
  created_at timestamptz not null default now()
);

-- Cuando se crea un usuario nuevo en Supabase Auth (Authentication > Add user),
-- se le crea automáticamente un perfil por defecto como "viewer" sin sede.
-- El administrador total debe luego asignarle el rol y sede correctos
-- desde el panel "Administrar usuarios" dentro de la app.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, email, nombre, rol, sede_id)
  values (new.id, new.email, split_part(new.email, '@', 1), 'viewer', null)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Funciones auxiliares para usar en las políticas (evitan recursión en RLS)
create or replace function public.get_my_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select rol from perfiles where id = auth.uid();
$$;

create or replace function public.get_my_sede()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select sede_id from perfiles where id = auth.uid();
$$;

-- ---------------------------------------------------------
-- 3. Artículos perdidos
-- ---------------------------------------------------------
create table if not exists articulos (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references sedes(id),
  categoria text not null,              -- 'Ropa' | 'Útiles escolares' | 'Otro'
  tipo text not null,                   -- ej. 'Polera', 'Chaqueta', 'Estuche', 'Botella'
  color text,
  talla text,
  tiene_nombre boolean not null default false,
  nombre_bordado text,                  -- nombre que aparece en la prenda/artículo, si tiene
  descripcion text,                     -- detalles adicionales
  foto_url text,                        -- URL pública de la foto en Supabase Storage
  lugar_encontrado text,
  fecha_encontrado date not null,
  registrado_por text not null,
  estado text not null default 'disponible', -- 'disponible' | 'retirado'
  retirado_por text,
  curso_retiro text,
  fecha_retiro date,
  created_at timestamptz not null default now()
);

-- Si la tabla ya existía de una versión anterior sin sedes, agrega la columna:
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'articulos' and column_name = 'sede_id'
  ) then
    alter table articulos add column sede_id uuid references sedes(id);
  end if;
end $$;

create index if not exists idx_articulos_estado on articulos (estado);
create index if not exists idx_articulos_categoria on articulos (categoria);
create index if not exists idx_articulos_sede on articulos (sede_id);
create index if not exists idx_articulos_fecha on articulos (fecha_encontrado desc);

-- ---------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------
alter table sedes enable row level security;
alter table perfiles enable row level security;
alter table articulos enable row level security;

-- Sedes: cualquier usuario autenticado puede leerlas (para filtros/formularios).
drop policy if exists "sedes_select_autenticados" on sedes;
create policy "sedes_select_autenticados"
  on sedes for select
  using (auth.role() = 'authenticated');

-- Sedes: solo admin_total puede crear/editar/borrar.
drop policy if exists "sedes_admin_total" on sedes;
create policy "sedes_admin_total"
  on sedes for all
  using (get_my_role() = 'admin_total')
  with check (get_my_role() = 'admin_total');

-- Perfiles: cada usuario ve su propio perfil; admin_total ve todos.
drop policy if exists "perfiles_select" on perfiles;
create policy "perfiles_select"
  on perfiles for select
  using (id = auth.uid() or get_my_role() = 'admin_total');

-- Perfiles: solo admin_total puede insertar/editar perfiles de otros usuarios
-- (asignar rol, sede, nombre).
drop policy if exists "perfiles_admin_total" on perfiles;
create policy "perfiles_admin_total"
  on perfiles for all
  using (get_my_role() = 'admin_total')
  with check (get_my_role() = 'admin_total');

-- Artículos: ver
-- - admin_total: ve todo
-- - admin_local / viewer con sede asignada: solo su sede
-- - viewer sin sede asignada: ve todas las sedes (solo lectura)
drop policy if exists "articulos_select" on articulos;
create policy "articulos_select"
  on articulos for select
  using (
    get_my_role() = 'admin_total'
    or sede_id = get_my_sede()
    or (get_my_role() = 'viewer' and get_my_sede() is null)
  );

-- Artículos: crear/editar
-- - admin_total: cualquier sede
-- - admin_local: solo su propia sede
-- - viewer: nunca
drop policy if exists "articulos_insert" on articulos;
create policy "articulos_insert"
  on articulos for insert
  with check (
    get_my_role() = 'admin_total'
    or (get_my_role() = 'admin_local' and sede_id = get_my_sede())
  );

drop policy if exists "articulos_update" on articulos;
create policy "articulos_update"
  on articulos for update
  using (
    get_my_role() = 'admin_total'
    or (get_my_role() = 'admin_local' and sede_id = get_my_sede())
  )
  with check (
    get_my_role() = 'admin_total'
    or (get_my_role() = 'admin_local' and sede_id = get_my_sede())
  );

-- Artículos: eliminar (solo admin_total, por seguridad)
drop policy if exists "articulos_delete" on articulos;
create policy "articulos_delete"
  on articulos for delete
  using (get_my_role() = 'admin_total');

-- ---------------------------------------------------------
-- 5. Storage: bucket de fotos
-- ---------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do nothing;

drop policy if exists "fotos_lectura_publica" on storage.objects;
create policy "fotos_lectura_publica"
  on storage.objects for select
  using (bucket_id = 'fotos');

-- Solo admin_total y admin_local pueden subir fotos (viewers no).
drop policy if exists "fotos_subida_autorizada" on storage.objects;
create policy "fotos_subida_autorizada"
  on storage.objects for insert
  with check (
    bucket_id = 'fotos'
    and get_my_role() in ('admin_total','admin_local')
  );

-- =========================================================
-- 6. Bootstrap: crear el primer administrador total
-- =========================================================
-- Después de crear tu primer usuario en
-- Authentication > Users > Add user (con su correo y contraseña),
-- ejecuta esto UNA VEZ reemplazando el correo:
--
-- update perfiles set rol = 'admin_total' where email = 'tu_correo@colegio.cl';
--
-- Ese usuario podrá entrar a la app y asignar roles/sedes al resto
-- desde el panel "Administrar usuarios".
