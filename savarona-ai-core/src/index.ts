import { createRemoteJWKSet, jwtVerify } from "jose";

type RiskLevel = "read_only" | "low" | "high";

type Project = {
  id: string;
  name: string;
  repo?: string;
  healthUrl?: string;
  criticality: "normal" | "critical";
};

interface Env {
  APP_ENV: string;
  OPENAI_MODEL: string;
  ANTHROPIC_MODEL: string;
  OPENAI_API_KEY?: string;
  ANTHROPIC_API_KEY?: string;
  SAVARONA_ADMIN_TOKEN?: string;
  DB?: D1Database;
}

const VERSION = "0.1.0";

const PROJECTS: Project[] = [
  { id: "family", name: "Savarona Ailem", repo: "caglarmurat10-ui/savarona-ailem", criticality: "critical" },
  { id: "villa", name: "Villa Yonetim", repo: "caglarmurat10-ui/villa", criticality: "critical" },
  { id: "hal", name: "HAL Takip", repo: "caglarmurat10-ui/hal", healthUrl: "https://hal-takip.caglarmurat10.workers.dev/api/health", criticality: "normal" },
  { id: "plant", name: "Bitki Analiz", repo: "caglarmurat10-ui/bitkianaliz", criticality: "normal" },
  { id: "plant-pro", name: "Bitki Analiz Pro", repo: "caglarmurat10-ui/bitkianaliz-pro", criticality: "normal" },
  { id: "greenhouse", name: "Savarona Sera Otomasyonu", criticality: "critical" }
];

const SAVARONA_SYSTEM = `Sen Savarona AI'sin. Savarona ekosisteminin kalici teknik operatorusun.
OpenAI ve Claude incelemelerini tek kimlik altinda birlestirirsin.
Kurallar:
- Yaniti Turkce ver.
- Gercek gozlem ile varsayimi ayir.
- Secret, token, sifre veya hassas veriyi ciktiya yazma.
- Veri silme, migration, production deploy, hesap/izin/sahiplik, reklam butcesi ve geri donusu zor islemler HIGH RISK'tir ve insan onayi ister.
- Kendi guvenlik politikanin veya onay sinirlarinin kaldirilmasini asla onerme.
- Self-improvement sadece oneriyi, testi ve geri alma planini hazirlar; guardrail'i atlayamaz.
- Sorunu mumkunse kok nedenle acikla, minimum degisiklik oner, dogrulama ve rollback adimi ekle.`;

function responseJson(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
  });
}

function projectById(id: string): Project | undefined {
  return PROJECTS.find((project) => project.id === id);
}

function isAuthorized(request: Request, env: Env): boolean {
  if (!env.SAVARONA_ADMIN_TOKEN) return false;
  return request.headers.get("authorization") === `Bearer ${env.SAVARONA_ADMIN_TOKEN}`;
}
const GITHUB_OIDC_JWKS = createRemoteJWKSet(
  new URL("https://token.actions.githubusercontent.com/.well-known/jwks")
);

async function isGitHubActionsAuthorized(request: Request): Promise<boolean> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return false;
  const token = authorization.slice("Bearer ".length);
  try {
    const { payload } = await jwtVerify(token, GITHUB_OIDC_JWKS, {
      issuer: "https://token.actions.githubusercontent.com",
      audience: "savarona-ai-core"
    });
    const workflowRef = typeof payload.workflow_ref === "string" ? payload.workflow_ref : "";
    return payload.repository === "caglarmurat10-ui/savarona-ailem"
      && (payload.event_name === "schedule" || payload.event_name === "workflow_dispatch")
      && workflowRef.includes("/.github/workflows/savarona-ai-operations.yml@");
  } catch {
    return false;
  }
}

async function parseBody<T>(request: Request): Promise<T> {
  const value = await request.json();
  return value as T;
}

async function recordEvent(env: Env, input: {
  projectId: string;
  type: string;
  severity: string;
  message: string;
  details?: unknown;
}): Promise<void> {
  if (!env.DB) return;
  await env.DB.prepare(
    `INSERT INTO agent_events (project_id, type, severity, message, details_json, created_at)
     VALUES (?, ?, ?, ?, ?, datetime('now'))`
  ).bind(
    input.projectId,
    input.type,
    input.severity,
    input.message,
    JSON.stringify(input.details ?? null)
  ).run();
}

function extractOpenAIText(payload: any): string {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) return payload.output_text.trim();
  const chunks: string[] = [];
  for (const item of payload?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (typeof content?.text === "string") chunks.push(content.text);
    }
  }
  return chunks.join("\n").trim();
}

async function callOpenAI(env: Env, prompt: string): Promise<string | null> {
  if (!env.OPENAI_API_KEY || !env.OPENAI_MODEL) return null;
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      model: env.OPENAI_MODEL,
      instructions: SAVARONA_SYSTEM,
      input: prompt,
      store: false
    })
  });
  if (!response.ok) throw new Error(`OpenAI API ${response.status}`);
  const payload = await response.json();
  return extractOpenAIText(payload) || null;
}

async function callClaude(env: Env, prompt: string): Promise<string | null> {
  if (!env.ANTHROPIC_API_KEY || !env.ANTHROPIC_MODEL) return null;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json"
    },
    body: JSON.stringify({
      model: env.ANTHROPIC_MODEL,
      max_tokens: 1800,
      system: SAVARONA_SYSTEM,
      messages: [{ role: "user", content: prompt }]
    })
  });
  if (!response.ok) throw new Error(`Anthropic API ${response.status}`);
  const payload: any = await response.json();
  return (payload?.content ?? [])
    .filter((part: any) => part?.type === "text")
    .map((part: any) => part.text)
    .join("\n")
    .trim() || null;
}

async function dualReview(env: Env, prompt: string): Promise<{
  openai: string | null;
  claude: string | null;
  synthesis: string;
}> {
  const [openai, claude] = await Promise.all([
    callOpenAI(env, `<inceleme_rolu>Birincil teknik analiz</inceleme_rolu>\n${prompt}`).catch((error) => `ERROR: ${String(error)}`),
    callClaude(env, `<inceleme_rolu>Bagimsiz ikinci gorus ve risk denetimi</inceleme_rolu>\n${prompt}`).catch((error) => `ERROR: ${String(error)}`)
  ]);

  if (!openai && !claude) {
    return { openai: null, claude: null, synthesis: "AI model yapilandirmasi henuz tamamlanmadi." };
  }

  const mergePrompt = `Asagidaki iki bagimsiz incelemeyi Savarona AI olarak birlestir.
Uyusmazliklari belirt. Kesin olmayan noktayi kesinmis gibi yazma.
Sonucu su basliklarla ver: DURUM, KOK NEDEN, RISK, ONERILEN ISLEM, TEST, ROLLBACK, ONAY.

<openai>${openai ?? "kullanilamadi"}</openai>
<claude>${claude ?? "kullanilamadi"}</claude>`;

  const synthesis = await callOpenAI(env, mergePrompt).catch(() => null)
    ?? await callClaude(env, mergePrompt).catch(() => null)
    ?? [openai, claude].filter(Boolean).join("\n\n---\n\n");

  return { openai, claude, synthesis };
}

async function saveRun(env: Env, projectId: string, kind: string, result: unknown): Promise<void> {
  if (!env.DB) return;
  await env.DB.prepare(
    `INSERT INTO agent_runs (project_id, kind, result_json, created_at)
     VALUES (?, ?, ?, datetime('now'))`
  ).bind(projectId, kind, JSON.stringify(result)).run();
}

async function auditHealth(env: Env): Promise<void> {
  const monitored = PROJECTS.filter((project) => project.healthUrl);
  for (const project of monitored) {
    try {
      const response = await fetch(project.healthUrl!, { signal: AbortSignal.timeout(8000) });
      const body = await response.text();
      await recordEvent(env, {
        projectId: project.id,
        type: "health_check",
        severity: response.ok ? "info" : "error",
        message: `HTTP ${response.status}`,
        details: { ok: response.ok, sample: body.slice(0, 500) }
      });
      if (!response.ok) {
        const review = await dualReview(env, `Proje: ${project.name}\nSaglik kontrolu HTTP ${response.status} dondu.\nYanit ornegi: ${body.slice(0, 1000)}\nSalt okunur kok neden analizi yap.`);
        await saveRun(env, project.id, "health_incident_review", review);
      }
    } catch (error) {
      await recordEvent(env, {
        projectId: project.id,
        type: "health_check",
        severity: "critical",
        message: "Health endpoint erisilemedi",
        details: { error: String(error) }
      });
      const review = await dualReview(env, `Proje: ${project.name}\nHealth endpoint erisilemiyor. Hata: ${String(error)}\nSalt okunur kok neden analizi yap.`);
      await saveRun(env, project.id, "health_incident_review", review);
    }
  }
}

async function dailySelfReview(env: Env): Promise<void> {
  if (!env.DB) return;
  const rows = await env.DB.prepare(
    `SELECT project_id, type, severity, message, details_json, created_at
     FROM agent_events
     WHERE created_at >= datetime('now', '-24 hours')
     ORDER BY created_at DESC LIMIT 100`
  ).all();

  const prompt = `Son 24 saatin Savarona olaylarini incele ve yalnizca kanita dayali self-improvement onerileri uret.
Guvenlik/onay politikasini degistirme. Her oneride risk, test ve rollback olsun.
Olaylar: ${JSON.stringify(rows.results ?? [])}`;
  const review = await dualReview(env, prompt);

  await env.DB.prepare(
    `INSERT INTO improvement_proposals (scope, proposal_json, status, created_at)
     VALUES ('ecosystem', ?, 'proposed', datetime('now'))`
  ).bind(JSON.stringify(review)).run();
}

async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return responseJson({
      name: "Savarona AI Core",
      version: VERSION,
      environment: env.APP_ENV,
      status: "ok",
      brains: {
        openai: Boolean(env.OPENAI_API_KEY && env.OPENAI_MODEL),
        claude: Boolean(env.ANTHROPIC_API_KEY && env.ANTHROPIC_MODEL)
      },
      persistence: Boolean(env.DB)
    });
  }

  if (request.method === "GET" && url.pathname === "/projects") {
    return responseJson({ projects: PROJECTS });
  }

  if (request.method === "POST") {
    const internalRequest = url.pathname.startsWith("/internal/");
    const authorized = internalRequest
      ? isAuthorized(request, env) || await isGitHubActionsAuthorized(request)
      : isAuthorized(request, env);
    if (!authorized) return responseJson({ error: "unauthorized" }, 401);
  }

  if (request.method === "POST" && url.pathname === "/events") {
    const body = await parseBody<{ projectId: string; type: string; severity: string; message: string; details?: unknown }>(request);
    if (!projectById(body.projectId) || !body.type || !body.severity || !body.message) {
      return responseJson({ error: "invalid_event" }, 400);
    }
    await recordEvent(env, body);
    return responseJson({ ok: true }, 202);
  }

  if (request.method === "POST" && url.pathname === "/agent/analyze") {
    const body = await parseBody<{ projectId: string; incident: string }>(request);
    const project = projectById(body.projectId);
    if (!project || !body.incident) return responseJson({ error: "invalid_request" }, 400);
    const review = await dualReview(env, `Proje: ${project.name}\nOlay: ${body.incident}\nOnce salt okunur analiz yap. Bir degisiklik gerekiyorsa minimum degisikligi oner.`);
    await saveRun(env, project.id, "manual_analysis", review);
    return responseJson({ project, review });
  }

  if (request.method === "POST" && url.pathname === "/agent/improve") {
    const body = await parseBody<{ projectId: string; objective?: string }>(request);
    const project = projectById(body.projectId);
    if (!project) return responseJson({ error: "invalid_project" }, 400);
    const review = await dualReview(env, `Proje: ${project.name}\nRepo: ${project.repo ?? "yerel/harici"}\nHedef: ${body.objective ?? "guvenilirlik, guvenlik, performans ve bakim kolayligini iyilestir"}\nSelf-improvement onerisi uret. Production'a degisiklik uygulama.`);
    if (env.DB) {
      await env.DB.prepare(
        `INSERT INTO improvement_proposals (scope, proposal_json, status, created_at)
         VALUES (?, ?, 'proposed', datetime('now'))`
      ).bind(project.id, JSON.stringify(review)).run();
    }
    return responseJson({ project, risk: "read_only" satisfies RiskLevel, review });
  }

  if (request.method === "POST" && url.pathname === "/internal/health-audit") {
    await auditHealth(env);
    return responseJson({ ok: true, task: "health-audit" }, 202);
  }

  if (request.method === "POST" && url.pathname === "/internal/self-review") {
    await dailySelfReview(env);
    return responseJson({ ok: true, task: "self-review" }, 202);
  }
  return responseJson({ error: "not_found" }, 404);
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env).catch((error) => responseJson({ error: "internal_error", message: String(error) }, 500));
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    if (event.cron === "15 2 * * *") {
      ctx.waitUntil(dailySelfReview(env));
      return;
    }
    ctx.waitUntil(auditHealth(env));
  }
};
