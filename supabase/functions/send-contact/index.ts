import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const APPS_SCRIPT_URL = Deno.env.get("APPS_SCRIPT_URL") ?? ""
const DEST_EMAIL = Deno.env.get("DEST_EMAIL") ?? "zunixe@gmail.com"
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? ""
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    })
  }

  try {
    const { name, email, message } = await req.json()

    if (!name || !email || !message) {
      return new Response(JSON.stringify({ error: "Semua field wajib diisi" }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      })
    }

    // Always save to database as fallback
    let dbSaved = false
    if (SUPABASE_URL && SUPABASE_SERVICE_KEY) {
      try {
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        const { error } = await supabase.from("contact_messages").insert({
          name,
          email,
          message,
          sent_via_email: false,
        })
        if (!error) dbSaved = true
      } catch (dbErr) {
        console.error("DB save error:", dbErr)
      }
    }

    // Check Apps Script URL
    if (!APPS_SCRIPT_URL) {
      if (dbSaved) {
        return new Response(JSON.stringify({
          success: true,
          warning: "Pesan tersimpan (email belum aktif)"
        }), {
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        })
      }
      return new Response(JSON.stringify({ error: "Email belum dikonfigurasi. Hubungi admin." }), {
        status: 503,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      })
    }

    // Send email via Google Apps Script
    try {
      const emailRes = await fetch(APPS_SCRIPT_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email, message }),
      })

      const emailBody = await emailRes.text()
      let emailResult: Record<string, unknown> = {}
      try { emailResult = JSON.parse(emailBody) } catch (_) {}

      if (emailResult.success) {
        // Mark as sent in DB
        if (dbSaved && SUPABASE_URL && SUPABASE_SERVICE_KEY) {
          try {
            const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
            await supabase.from("contact_messages")
              .update({ sent_via_email: true })
              .eq("email", email)
              .eq("sent_via_email", false)
              .order("created_at", { ascending: false })
              .limit(1)
          } catch (_) {}
        }
        return new Response(JSON.stringify({ success: true }), {
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        })
      } else {
        const errMsg = emailResult.error ?? emailBody
        console.error("Apps Script error:", errMsg)
        if (dbSaved) {
          return new Response(JSON.stringify({
            success: true,
            warning: "Email gagal, pesan tersimpan di database",
            smtp_error: String(errMsg),
          }), {
            headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
          })
        }
        return new Response(JSON.stringify({ error: "Email gagal: " + errMsg }), {
          status: 500,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        })
      }
    } catch (emailErr) {
      const msg = emailErr instanceof Error ? emailErr.message : String(emailErr)
      console.error("Email error:", msg)
      if (dbSaved) {
        return new Response(JSON.stringify({
          success: true,
          warning: "Email gagal, pesan tersimpan di database",
          smtp_error: msg,
        }), {
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        })
      }
      return new Response(JSON.stringify({ error: "Email gagal: " + msg }), {
        status: 500,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      })
    }
  } catch (err) {
    console.error("Send error:", err)
    return new Response(JSON.stringify({
      error: "Server error: " + (err instanceof Error ? err.message : String(err))
    }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    })
  }
})
