import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  lerConfigCaptcha,
  MENSAGEM_CAPTCHA_FALHOU,
  MENSAGEM_CAPTCHA_INDISPONIVEL,
  type ConfigCaptcha,
} from "../../lib/captcha";

/**
 * Hook único de CAPTCHA (Cloudflare Turnstile) para as telas de Auth.
 *
 * Regras que toda tela herda daqui, em vez de copiar:
 *  - sem token válido, `pronto` é false e a tela NÃO chama o Supabase Auth;
 *  - o token é de uso único: `consumir()` entrega o token, apaga-o e reseta o
 *    widget, que emite um novo para a próxima tentativa (acerto ou erro);
 *  - expiração, erro e timeout do widget apagam o token;
 *  - falha ao carregar o script do Turnstile mantém `pronto` false (falha
 *    fechada) — nunca libera o envio sem verificação;
 *  - sem site key em Production: `bloqueado`, com aviso explícito.
 *
 * Só a site key PÚBLICA passa por aqui. O secret fica no Supabase Dashboard.
 */

const URL_SCRIPT = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

type OpcoesWidget = {
  sitekey: string;
  action?: string;
  language?: string;
  theme?: "light" | "dark" | "auto";
  size?: "normal" | "flexible" | "compact";
  callback?: (token: string) => void;
  "expired-callback"?: () => void;
  "error-callback"?: () => void;
  "timeout-callback"?: () => void;
};

type ApiTurnstile = {
  render: (el: HTMLElement, opcoes: OpcoesWidget) => string;
  reset: (widgetId?: string) => void;
  remove: (widgetId?: string) => void;
};

declare global {
  interface Window {
    turnstile?: ApiTurnstile;
  }
}

let carregandoScript: Promise<ApiTurnstile> | null = null;

/** Carrega o script oficial uma vez por página. */
function carregarTurnstile(): Promise<ApiTurnstile> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (carregandoScript) return carregandoScript;
  carregandoScript = new Promise<ApiTurnstile>((resolver, rejeitar) => {
    const s = document.createElement("script");
    s.src = URL_SCRIPT;
    s.async = true;
    s.defer = true;
    s.onload = () =>
      window.turnstile ? resolver(window.turnstile) : rejeitar(new Error("turnstile_indisponivel"));
    s.onerror = () => rejeitar(new Error("turnstile_script"));
    document.head.appendChild(s);
  }).catch((e) => {
    carregandoScript = null; // permite nova tentativa em outra montagem
    throw e;
  });
  return carregandoScript;
}

export type CaptchaAuth = {
  config: ConfigCaptcha;
  /** Pode enviar a operação de Auth agora? */
  pronto: boolean;
  /** Configuração ausente em Production: nenhuma operação deve ser enviada. */
  bloqueado: boolean;
  /** Elemento a renderizar no formulário (widget + avisos). */
  widget: ReactNode;
  /** Entrega o token atual (uso único) e prepara o próximo. */
  consumir: () => string | undefined;
  /**
   * Para uma SEGUNDA chamada de Auth no mesmo envio: espera o próximo token
   * (o widget já foi resetado por `consumir`). Devolve null se não chegar a
   * tempo — a tela então pede uma nova tentativa, sem chamar o Auth.
   */
  proximoToken: (timeoutMs?: number) => Promise<string | undefined | null>;
};

export function useCaptchaAuth(acao: string): CaptchaAuth {
  const config = useMemo(() => lerConfigCaptcha(), []);
  // Callback ref: o formulário pode aparecer só numa etapa posterior; o
  // widget monta quando o container existir e sai quando ele sair.
  const [container, setContainer] = useState<HTMLDivElement | null>(null);
  const widgetIdRef = useRef<string | null>(null);
  const tokenRef = useRef<string | null>(null);
  const esperaRef = useRef<((t: string) => void) | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);

  const limparToken = useCallback(() => {
    tokenRef.current = null;
    setToken(null);
  }, []);

  useEffect(() => {
    if (config.modo !== "turnstile" || !container) return;
    let ativo = true;
    carregarTurnstile()
      .then((api) => {
        if (!ativo || widgetIdRef.current) return;
        widgetIdRef.current = api.render(container, {
          sitekey: config.siteKey,
          action: acao,
          language: "pt-br",
          theme: "light",
          size: "flexible",
          callback: (t) => {
            tokenRef.current = t;
            setToken(t);
            setAviso(null);
            const espera = esperaRef.current;
            esperaRef.current = null;
            espera?.(t);
          },
          "expired-callback": () => {
            limparToken();
            setAviso("A verificação de segurança expirou. Ela será refeita automaticamente.");
          },
          "error-callback": () => {
            limparToken();
            setAviso(MENSAGEM_CAPTCHA_FALHOU);
          },
          "timeout-callback": () => {
            limparToken();
            setAviso(MENSAGEM_CAPTCHA_FALHOU);
          },
        });
      })
      .catch(() => {
        if (ativo) setAviso("Não foi possível carregar a verificação de segurança. Recarregue a página.");
      });
    return () => {
      ativo = false;
      if (widgetIdRef.current && window.turnstile) window.turnstile.remove(widgetIdRef.current);
      widgetIdRef.current = null;
      esperaRef.current = null;
      limparToken();
    };
  }, [config, acao, container, limparToken]);

  const consumir = useCallback((): string | undefined => {
    if (config.modo !== "turnstile") return undefined;
    const atual = tokenRef.current ?? undefined;
    limparToken();
    if (widgetIdRef.current && window.turnstile) window.turnstile.reset(widgetIdRef.current);
    return atual;
  }, [config, limparToken]);

  const proximoToken = useCallback(
    (timeoutMs = 20000): Promise<string | undefined | null> => {
      if (config.modo !== "turnstile") return Promise.resolve(undefined);
      if (tokenRef.current) return Promise.resolve(consumir());
      return new Promise((resolver) => {
        const limite = window.setTimeout(() => {
          esperaRef.current = null;
          resolver(null);
        }, timeoutMs);
        esperaRef.current = () => {
          window.clearTimeout(limite);
          resolver(consumir());
        };
      });
    },
    [config, consumir]
  );

  const bloqueado = config.modo === "erro_config";
  const pronto = config.modo === "desligado" || (config.modo === "turnstile" && token !== null);

  const widget =
    config.modo === "desligado" ? null : bloqueado ? (
      <p role="alert" className="aviso-erro">
        {MENSAGEM_CAPTCHA_INDISPONIVEL}
      </p>
    ) : (
      <div>
        <div ref={setContainer} data-testid="captcha-turnstile" className="min-h-[65px]" />
        {aviso && (
          <p role="status" className="mt-2 text-sm text-tinta/70">
            {aviso}
          </p>
        )}
      </div>
    );

  return { config, pronto, bloqueado, widget, consumir, proximoToken };
}
