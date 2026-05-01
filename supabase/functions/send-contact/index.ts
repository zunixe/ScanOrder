import "@supabase/functions-js/edge-runtime.d.ts"
import { SmtpClient } from "https://deno.land/x/smtp@v0.7.0/mod.ts"

const SMTP_HOST = Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com"
const SMTP_PORT = Number(Deno.env.get("SMTP_PORT") ?? 587)
const SMTP_USER = Deno.env.get("SMTP_USER") ?? ""
const SMTP_PASS = Deno.env.get("SMTP_PASS") ?? ""
const DEST_EMAIL = Deno.env.get("DEST_EMAIL") ?? "zunixe@gmail.com"

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

    const client = new SmtpClient()
    await client.connectTLS({
      hostname: SMTP_HOST,
      port: SMTP_PORT,
      username: SMTP_USER,
      password: SMTP_PASS,
    })

    await client.send({
      from: SMTP_USER,
      to: DEST_EMAIL,
      subject: `[ScanOrder] Pesan dari ${name}`,
      content: `Nama: ${name}\nEmail: ${email}\n\nPesan:\n${message}`,
      html: `
        <div style="font-family:sans-serif;max-width:500px;margin:0 auto">
          <h2 style="color:#2563EB">Pesan dari ScanOrder</h2>
          <p><strong>Nama:</strong> ${name}</p>
          <p><strong>Email:</strong> ${email}</p>
          <hr style="border:none;border-top:1px solid #eee"/>
          <p style="white-space:pre-wrap">${message}</p>
        </div>
      `,
    })

    await client.close()

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    })
  } catch (err) {
    console.error("Send error:", err)
    return new Response(JSON.stringify({ error: "Gagal mengirim pesan" }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    })
  }
})
