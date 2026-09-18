import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json" };
const maxAuthenticationAgeSeconds = 5 * 60;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ message: "Method not allowed" }), { status: 405, headers: jsonHeaders });
  }

  const authorization = request.headers.get("Authorization");
  const token = authorization?.startsWith("Bearer ") ? authorization.slice(7) : null;
  if (!token) return response(401, "Authentication required");

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return response(500, "Account deletion is not configured");

  const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return response(401, "Your session is no longer valid");

  const issuedAt = jwtIssuedAt(token);
  if (!issuedAt || Math.floor(Date.now() / 1000) - issuedAt > maxAuthenticationAgeSeconds) {
    return response(401, "Re-enter your password before deleting your account");
  }

  const userID = userData.user.id;
  try {
    const paths = await listFiles(admin, "post-photos", userID);
    for (let index = 0; index < paths.length; index += 100) {
      const { error } = await admin.storage.from("post-photos").remove(paths.slice(index, index + 100));
      if (error) throw error;
    }

    const { error } = await admin.auth.admin.deleteUser(userID, false);
    if (error) throw error;
    return new Response(JSON.stringify({ deleted: true }), { status: 200, headers: jsonHeaders });
  } catch (error) {
    console.error("delete-account", userID, error);
    return response(500, "Account deletion could not be completed. Please try again.");
  }
});

function response(status: number, message: string) {
  return new Response(JSON.stringify({ message }), { status, headers: jsonHeaders });
}

function jwtIssuedAt(token: string): number | null {
  try {
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload)).iat ?? null;
  } catch {
    return null;
  }
}

async function listFiles(client: ReturnType<typeof createClient>, bucket: string, root: string): Promise<string[]> {
  const files: string[] = [];
  const pending = [root];
  while (pending.length > 0) {
    const prefix = pending.pop()!;
    let offset = 0;
    while (true) {
      const { data, error } = await client.storage.from(bucket).list(prefix, { limit: 100, offset });
      if (error) throw error;
      for (const entry of data ?? []) {
        const path = `${prefix}/${entry.name}`;
        if (entry.id) files.push(path); else pending.push(path);
      }
      if (!data || data.length < 100) break;
      offset += data.length;
    }
  }
  return files;
}
