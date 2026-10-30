/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  /**
   * Site key PÚBLICA do Cloudflare Turnstile (CAPTCHA do Supabase Auth).
   * O SECRET do Turnstile nunca entra aqui: fica só no Supabase Dashboard.
   * Ausente em build de Production → login/cadastro/reset falham fechados.
   */
  readonly VITE_TURNSTILE_SITE_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
