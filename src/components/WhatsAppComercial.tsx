import { useEffect, useRef, useState } from "react";
import { useLocation } from "react-router-dom";
import {
  WHATSAPP_COMERCIAL,
  WHATSAPP_COMERCIAL_URL,
  whatsAppFlutuanteVisivel,
} from "../content/whatsapp";

/** Glifo do WhatsApp (decorativo; o nome acessível fica no link). */
export function IconeWhatsApp({ className = "h-7 w-7" }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 32 32" className={className} fill="currentColor">
      <path d="M16.04 3C8.86 3 3.02 8.83 3.02 16c0 2.29.6 4.53 1.74 6.5L3 29l6.68-1.75A13 13 0 0 0 16.04 29C23.2 29 29 23.17 29 16S23.2 3 16.04 3Zm0 23.8c-1.95 0-3.86-.52-5.53-1.51l-.4-.24-3.96 1.04 1.06-3.86-.26-.4A10.77 10.77 0 0 1 5.25 16c0-5.95 4.84-10.79 10.8-10.79 5.94 0 10.75 4.84 10.75 10.79 0 5.96-4.81 10.8-10.76 10.8Zm5.92-8.08c-.32-.16-1.92-.95-2.22-1.06-.3-.11-.51-.16-.73.16-.21.32-.84 1.06-1.03 1.27-.19.22-.38.24-.7.08-.32-.16-1.37-.5-2.6-1.6-.96-.86-1.61-1.92-1.8-2.24-.19-.32-.02-.5.14-.66.15-.14.32-.38.48-.56.16-.19.21-.32.32-.54.1-.21.05-.4-.03-.56-.08-.16-.73-1.76-1-2.41-.26-.63-.53-.55-.73-.56h-.62c-.22 0-.56.08-.86.4-.3.32-1.13 1.1-1.13 2.69 0 1.58 1.16 3.12 1.32 3.33.16.22 2.28 3.48 5.52 4.88.77.33 1.37.53 1.84.68.77.25 1.48.21 2.03.13.62-.09 1.92-.78 2.19-1.54.27-.76.27-1.41.19-1.54-.08-.14-.3-.22-.62-.38Z" />
    </svg>
  );
}

/** Controles que o botão nunca pode cobrir, em qualquer largura. */
export const SELETOR_CONTROLES =
  'a[href], button, input, select, textarea, summary, label, [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="tab"], [contenteditable="true"], [tabindex]:not([tabindex="-1"])';

type Retangulo = { left: number; right: number; top: number; bottom: number };

/** Interseção com folga de `margem` px em volta do botão. */
export function intersecta(a: Retangulo, b: Retangulo, margem = 6): boolean {
  return (
    b.right > a.left - margem &&
    b.left < a.right + margem &&
    b.bottom > a.top - margem &&
    b.top < a.bottom + margem
  );
}

/** Verdadeiro quando algum controle visível está sob (ou colado a) o botão. */
export function cobreControle(botao: HTMLElement, raiz: ParentNode = document): boolean {
  const r = botao.getBoundingClientRect();
  for (const el of raiz.querySelectorAll<HTMLElement>(SELETOR_CONTROLES)) {
    if (el === botao || botao.contains(el) || el.contains(botao)) continue;
    const q = el.getBoundingClientRect();
    if (q.width === 0 || q.height === 0) continue;
    if (!intersecta(r, q)) continue;
    const estilo = window.getComputedStyle(el);
    if (estilo.visibility === "hidden" || estilo.display === "none") continue;
    return true;
  }
  return false;
}

/**
 * Botão flutuante do WhatsApp comercial, no canto inferior direito das
 * páginas públicas (lista fechada em `whatsAppFlutuanteVisivel`). Fica sob o
 * cabeçalho fixo (z-40 < z-50) e respeita a área segura do iPhone.
 *
 * Em qualquer largura, sai de cena (sem ocupar o toque nem o foco) enquanto
 * houver link, botão, campo ou outro controle sob ele — durante e depois da
 * rolagem, no redimensionamento e quando o conteúdo muda — e volta assim que
 * a área fica livre. Sem breakpoint: não depende de barra de rolagem nem zoom.
 */
export default function WhatsAppFlutuante() {
  const { pathname } = useLocation();
  const visivel = whatsAppFlutuanteVisivel(pathname);
  const ref = useRef<HTMLAnchorElement>(null);
  const [recolhido, setRecolhido] = useState(false);

  useEffect(() => {
    if (!visivel) return;
    let quadro = 0;
    let espera: number | undefined;
    const avaliar = () => {
      quadro = 0;
      const botao = ref.current;
      if (!botao) return;
      // Com foco no próprio botão (teclado), ele não some.
      const cobrir = document.activeElement !== botao && cobreControle(botao);
      setRecolhido(cobrir);
    };
    const agendar = () => {
      if (!quadro) quadro = window.requestAnimationFrame(avaliar);
    };
    // Conteúdo carregado depois (listas, avisos) também é reavaliado.
    const observador = new MutationObserver(() => {
      window.clearTimeout(espera);
      espera = window.setTimeout(agendar, 120);
    });
    observador.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "hidden", "open"] });
    window.addEventListener("scroll", agendar, { passive: true });
    window.addEventListener("resize", agendar);
    // Saída do foco (Tab, clique fora, blur) sem rolagem também reavalia.
    const botaoAtual = ref.current;
    botaoAtual?.addEventListener("blur", agendar);
    agendar();
    return () => {
      observador.disconnect();
      window.removeEventListener("scroll", agendar);
      window.removeEventListener("resize", agendar);
      botaoAtual?.removeEventListener("blur", agendar);
      window.cancelAnimationFrame(quadro);
      window.clearTimeout(espera);
      setRecolhido(false);
    };
  }, [visivel, pathname]);

  if (!visivel) return null;
  return (
    <a
      ref={ref}
      href={WHATSAPP_COMERCIAL_URL}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={WHATSAPP_COMERCIAL.rotuloAcessivel}
      title={WHATSAPP_COMERCIAL.rotuloAcessivel}
      data-testid="whatsapp-flutuante"
      data-recolhido={recolhido ? "true" : undefined}
      aria-hidden={recolhido || undefined}
      tabIndex={recolhido ? -1 : undefined}
      className={`fixed z-40 flex h-14 w-14 items-center justify-center rounded-full border-2 border-[#128C7E] bg-[#25D366] text-white shadow-[0_8px_24px_-8px_rgba(0,0,0,0.45)] transition hover:scale-105 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-[#128C7E]/40 motion-reduce:transition-none motion-reduce:hover:scale-100 sm:h-[3.75rem] sm:w-[3.75rem] ${
        recolhido ? "pointer-events-none invisible opacity-0" : ""
      }`}
      style={{
        right: "max(1rem, env(safe-area-inset-right))",
        bottom: "max(1rem, env(safe-area-inset-bottom))",
      }}
    >
      <IconeWhatsApp className="h-8 w-8" />
    </a>
  );
}
