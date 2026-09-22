// ============================================================
// Edge Function: verify-purchase
//
// Verifikasi receipt Google Play secara SERVER-SIDE sebelum
// tier subscription dianggap sah.
//
// Flow:
//   1. Client (app) POST { productId, purchaseToken, orderId? }
//      dengan Authorization: Bearer <user JWT>
//   2. Function verifikasi identitas user (JWT) + token purchase
//      ke Google Play Developer API (service account)
//   3. Jika aktif & belum expired → set tier di user_subscriptions
//      (pakai service_role → trigger guard melewatinya) dan
//      tandai purchase_receipts.verified = true
//
// Secrets yang wajib diset:
//   supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='<isi JSON key>'
//   supabase secrets set ANDROID_PACKAGE_NAME=com.scanorder.scanorder
//
// Deploy:
//   supabase functions deploy verify-purchase
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? ""
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const ANDROID_PACKAGE_NAME = Deno.env.get("ANDROID_PACKAGE_NAME") ?? "com.scanorder.scanorder"

// Service account: full JSON atau field terpisah
const GOOGLE_SERVICE_ACCOUNT_JSON = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? ""
const GOOGLE_CLIENT_EMAIL = Deno.env.get("GOOGLE_CLIENT_EMAIL") ?? ""
const GOOGLE_PRIVATE_KEY = Deno.env.get("GOOGLE_PRIVATE_KEY") ?? ""

// Product ID → tier (harus sama dengan lib/services/iap_service.dart)
const PRODUCT_TIER_MAP: Record<string, string> = {
  scanorder_basic_monthly: "basic",
  scanorder_pro_monthly: "pro",
  scanorder_team_monthly: "unlimited",
}

// Tier → kuota scan/bulan (harus sama dengan lib/services/quota_service.dart)
const TIER_ALLOWANCE: Record<string, number> = {
  free: 200,
  basic: 3000,
  pro: 9000,
  unlimited: -1,
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  })
}

// ── OAuth2 service account (RS256 JWT via WebCrypto) ────────────────

function serviceAccountCreds(): { email: string; privateKey: string } | null {
  if (GOOGLE_SERVICE_ACCOUNT_JSON) {
    try {
      const parsed = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON)
      return { email: parsed.client_email, privateKey: parsed.private_key }
    } catch {
      return null
    }
  }
  if (GOOGLE_CLIENT_EMAIL && GOOGLE_PRIVATE_KEY) {
    return { email: GOOGLE_CLIENT_EMAIL, privateKey: GOOGLE_PRIVATE_KEY }
  }
  return null
}

function pemToPkcs8Der(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "")
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

function b64urlEncode(data: Uint8Array): string {
  let bin = ""
  for (const b of data) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function getGoogleAccessToken(): Promise<string> {
  const creds = serviceAccountCreds()
  if (!creds) throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON belum dikonfigurasi")

  const now = Math.floor(Date.now() / 1000)
  const header = b64urlEncode(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })))
  const claim = b64urlEncode(new TextEncoder().encode(JSON.stringify({
    iss: creds.email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })))
  const unsigned = `${header}.${claim}`

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8Der(creds.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  )
  const assertion = `${unsigned}.${b64urlEncode(new Uint8Array(sig))}`

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  })
  if (!res.ok) throw new Error(`Google token endpoint error: ${await res.text()}`)
  const data = await res.json()
  return data.access_token as string
}

// ── Google Play verification ────────────────────────────────────────

interface PlayVerification {
  active: boolean
  expiryTime: string | null
  productId: string
  purchaseTime?: string
}

async function verifyWithPlay(
  accessToken: string,
  productId: string,
  purchaseToken: string,
): Promise<PlayVerification> {
  const auth = { Authorization: `Bearer ${accessToken}` }

  // 1) Subscriptions v2 API (Play Billing Library 5+)
  const v2Res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE_NAME}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: auth },
  )
  if (v2Res.ok) {
    const data = await v2Res.json()
    // SUBSCRIPTION_STATE_ACTIVE | IN_GRACE_PERIOD → masih aktif
    const state: string = data.subscriptionState ?? ""
    const activeStates = ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"]
    const items: Array<{ productId?: string; expiryTime?: string }> = data.lineItems ?? []
    const item =
      items.find((i) => i.productId === productId) ??
      items.sort((a, b) => (b.expiryTime ?? "").localeCompare(a.expiryTime ?? ""))[0]
    const expiry = item?.expiryTime ?? data.expiryTime ?? null
    const expired = expiry ? new Date(expiry).getTime() < Date.now() : true
    return {
      active: activeStates.includes(state) && !expired,
      expiryTime: expiry,
      productId: item?.productId ?? productId,
      purchaseTime: data.startTime,
    }
  }
  if (v2Res.status !== 404) {
    throw new Error(`Play API v2 error ${v2Res.status}: ${await v2Res.text()}`)
  }

  // 2) Fallback legacy subscriptions.get
  const legacyRes = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE_NAME}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: auth },
  )
  if (!legacyRes.ok) {
    throw new Error(`Play API legacy error ${legacyRes.status}: ${await legacyRes.text()}`)
  }
  const legacy = await legacyRes.json()
  const expiryMs = Number(legacy.expiryTimeMillis ?? 0)
  // paymentState: 1 = received, 2 = free trial; cancelReason: ada = dibatalkan
  const paid = legacy.paymentState === 1 || legacy.paymentState === 2
  return {
    active: paid && !legacy.cancelReason && expiryMs > Date.now(),
    expiryTime: expiryMs ? new Date(expiryMs).toISOString() : null,
    productId,
    purchaseTime: legacy.startTimeMillis
      ? new Date(Number(legacy.startTimeMillis)).toISOString()
      : undefined,
  }
}

// ── Main handler ────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  // 1. Verifikasi user JWT
  const authHeader = req.headers.get("Authorization") ?? ""
  const userToken = authHeader.replace("Bearer ", "").trim()
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return json({ error: "Server belum dikonfigurasi" }, 503)
  }
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  const { data: userData, error: userErr } = await supabase.auth.getUser(userToken)
  if (userErr || !userData?.user) {
    return json({ error: "Unauthorized" }, 401)
  }
  const userId = userData.user.id
  const userEmail = userData.user.email ?? ""

  // 2. Parse body
  let body: { productId?: string; purchaseToken?: string; orderId?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }
  const { productId, purchaseToken, orderId } = body
  if (!productId || !purchaseToken) {
    return json({ error: "productId dan purchaseToken wajib" }, 400)
  }
  const tier = PRODUCT_TIER_MAP[productId]
  if (!tier) {
    return json({ error: `Product tidak dikenal: ${productId}` }, 400)
  }

  // 3. Verifikasi ke Google Play
  let verification: PlayVerification
  try {
    const accessToken = await getGoogleAccessToken()
    verification = await verifyWithPlay(accessToken, productId, purchaseToken)
  } catch (e) {
    console.error("verify-purchase: play verification failed:", e)
    return json({ error: "Verifikasi Google Play gagal", detail: String(e) }, 502)
  }

  if (!verification.active) {
    // Token tidak aktif/expired → catat verified=false, jangan set tier
    await supabase
      .from("purchase_receipts")
      .update({ verified: false })
      .eq("user_id", userId)
      .eq("purchase_token", purchaseToken)
    return json({ success: false, reason: "subscription_not_active" }, 200)
  }

  // 4. Set tier via service_role (trigger guard melewatinya karena
  //    claims role = service_role)
  const now = new Date().toISOString()
  const { data: existing } = await supabase
    .from("user_subscriptions")
    .select("cycle_used")
    .eq("user_id", userId)
    .maybeSingle()

  const { error: subErr } = await supabase.from("user_subscriptions").upsert({
    user_id: userId,
    email: userEmail,
    tier,
    active_from: verification.purchaseTime ?? now,
    active_until: verification.expiryTime ?? null,
    cycle_allowance: TIER_ALLOWANCE[tier] ?? 200,
    cycle_used: existing?.cycle_used ?? 0,
    updated_at: now,
  }, { onConflict: "user_id" })

  if (subErr) {
    console.error("verify-purchase: upsert subscription error:", subErr)
    return json({ error: "Gagal menyimpan subscription", detail: subErr.message }, 500)
  }

  // 5. Tandai receipt terverifikasi
  await supabase
    .from("purchase_receipts")
    .update({ verified: true })
    .eq("user_id", userId)
    .eq("purchase_token", purchaseToken)

  return json({
    success: true,
    tier,
    active_until: verification.expiryTime,
  })
})
