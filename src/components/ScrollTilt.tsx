import { useEffect, useRef, useState } from "react";

/**
 * ScrollTilt — adaptação do "ContainerScroll" (skill UI/UX Pro Max)
 * para React + Vite, SEM dependência de framer-motion.
 *
 * O conteúdo entra inclinado em 3D (rotateX ~18°) e vai se
 * endireitando e assentando conforme o usuário rola — como uma tela
 * "pousando" na página. Respeita prefers-reduced-motion (fica
 * estático) e usa requestAnimationFrame para suavidade.
 */
export default function ScrollTilt({
  children,
}: {
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [progresso, setProgresso] = useState(0); // 0 = longe, 1 = assentado
  const [mobile, setMobile] = useState(false);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setProgresso(1);
      return;
    }

    const medir = () => setMobile(window.innerWidth < 768);
    medir();

    let raf = 0;
    const calcular = () => {
      const el = ref.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const vh = window.innerHeight;
      // 0 quando o topo do elemento entra na tela; 1 quando já subiu ~85% dela
      const p = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.85)));
      setProgresso(p);
    };

    const aoRolar = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(calcular);
    };

    calcular();
    window.addEventListener("scroll", aoRolar, { passive: true });
    window.addEventListener("resize", medir);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("scroll", aoRolar);
      window.removeEventListener("resize", medir);
    };
  }, []);

  const rotacao = 18 * (1 - progresso);
  const escala = mobile
    ? 0.92 + 0.08 * progresso
    : 1.04 - 0.04 * progresso;

  return (
    <div style={{ perspective: "1100px" }}>
      <div
        ref={ref}
        style={{
          transform: `rotateX(${rotacao}deg) scale(${escala})`,
          transformStyle: "preserve-3d",
          willChange: "transform",
        }}
      >
        {children}
      </div>
    </div>
  );
}
