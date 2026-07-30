// =========================================================
// Edge Function: crear-usuario
// =========================================================
// Esto NO va en index.html. Se pega tal cual en:
// Supabase Dashboard > Edge Functions > Deploy a new function > Via Editor
// con el nombre de función: crear-usuario
//
// Permite que un administrador total cree cuentas nuevas
// (correo + contraseña) directamente desde la app, sin tener
// que entrar manualmente a Authentication > Users cada vez.
//
// La clave "service role" (la que puede crear usuarios) NUNCA
// se expone al navegador: vive solo dentro de esta función,
// inyectada automáticamente por Supabase como variable de entorno.
// =========================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No autorizado." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Cliente que actúa como quien llama, para verificar quién es y su rol.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user: callerUser }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerUser) {
      return new Response(JSON.stringify({ error: "Sesión inválida." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: callerPerfil } = await callerClient
      .from("perfiles")
      .select("rol")
      .eq("id", callerUser.id)
      .single();

    if (!callerPerfil || callerPerfil.rol !== "admin_total") {
      return new Response(JSON.stringify({ error: "Solo un administrador total puede crear usuarios." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { email, password, nombre, rol, sede_id } = body;

    if (!email || !password) {
      return new Response(JSON.stringify({ error: "Falta correo o contraseña." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (password.length < 6) {
      return new Response(JSON.stringify({ error: "La contraseña debe tener al menos 6 caracteres." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!["admin_total", "admin_local", "viewer"].includes(rol)) {
      return new Response(JSON.stringify({ error: "Rol inválido." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Cliente con privilegios de administrador (usa la service role key).
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: newUser, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (createErr) {
      return new Response(JSON.stringify({ error: createErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // El trigger ya creó una fila en "perfiles" con rol viewer por defecto;
    // aquí la actualizamos con los datos reales (upsert por seguridad).
    const { error: profileErr } = await adminClient
      .from("perfiles")
      .upsert({
        id: newUser.user.id,
        email: newUser.user.email,
        nombre: nombre || null,
        rol,
        sede_id: rol === "admin_total" ? null : (sede_id || null),
      });

    if (profileErr) {
      return new Response(JSON.stringify({ error: profileErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, id: newUser.user.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
