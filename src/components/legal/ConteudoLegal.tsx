import { Fragment, type ReactNode } from "react";

/**
 * Renderização de conteúdo legal vindo do banco.
 *
 * REGRA DURA: nada de `dangerouslySetInnerHTML`.
 *
 * O conteúdo é texto que veio de uma tabela. Injetá-lo como HTML daria a quem
 * escreve no banco a capacidade de executar script na sessão de quem lê a
 * página legal — que é pública e, por desenho, a mais exposta do site. Em vez
 * disso o Markdown é convertido em elementos React, e qualquer coisa fora do
 * subconjunto reconhecido vira texto literal.
 *
 * O subconjunto é deliberadamente pequeno, porque corresponde ao que os
 * documentos congelados usam: títulos, parágrafos, negrito, itens de lista,
 * citação e régua. Sem link, sem imagem, sem HTML embutido — nenhum dos três
 * aparece nos documentos, e cada um seria uma superfície a mais.
 */

/** Negrito `**...**`. O resto da linha fica literal, inclusive `<script>`. */
function inline(texto: string): ReactNode[] {
  const partes: ReactNode[] = [];
  const re = /\*\*([^*]+)\*\*/g;
  let ultimo = 0;
  let m: RegExpExecArray | null;
  let i = 0;
  while ((m = re.exec(texto)) !== null) {
    if (m.index > ultimo) partes.push(texto.slice(ultimo, m.index));
    partes.push(<strong key={`b${i++}`}>{m[1]}</strong>);
    ultimo = m.index + m[0].length;
  }
  if (ultimo < texto.length) partes.push(texto.slice(ultimo));
  return partes.length > 0 ? partes : [texto];
}

export default function ConteudoLegal({ markdown }: { markdown: string }) {
  const linhas = markdown.split("\n");
  const blocos: ReactNode[] = [];
  let lista: string[] = [];

  const fecharLista = (chave: string) => {
    if (lista.length === 0) return;
    blocos.push(
      <ul key={chave} className="my-4 space-y-2 pl-5">
        {lista.map((item, i) => (
          <li key={i} className="list-disc leading-7 text-tinta/80">
            {inline(item)}
          </li>
        ))}
      </ul>
    );
    lista = [];
  };

  linhas.forEach((linha, i) => {
    const t = linha.trim();

    if (t.startsWith("- ")) {
      lista.push(t.slice(2));
      return;
    }
    fecharLista(`ul${i}`);

    if (t.length === 0) return;

    if (t === "---") {
      blocos.push(<hr key={i} className="my-8 border-tinta/15" />);
      return;
    }
    if (t.startsWith("### ")) {
      blocos.push(
        <h3 key={i} className="mt-8 text-lg font-bold leading-snug">
          {inline(t.slice(4))}
        </h3>
      );
      return;
    }
    if (t.startsWith("## ")) {
      blocos.push(
        <h2 key={i} className="mt-10 text-xl font-bold leading-snug sm:text-2xl">
          {inline(t.slice(3))}
        </h2>
      );
      return;
    }
    if (t.startsWith("# ")) {
      // O título do documento já é exibido no cabeçalho da página; aqui ele
      // vira um h2 para não disputar com o h1 da página.
      blocos.push(
        <h2 key={i} className="mt-10 text-xl font-bold leading-snug sm:text-2xl">
          {inline(t.slice(2))}
        </h2>
      );
      return;
    }
    if (t.startsWith("> ")) {
      blocos.push(
        <blockquote
          key={i}
          className="my-5 border-l-4 border-ciano/60 pl-4 leading-7 text-tinta/75"
        >
          {inline(t.slice(2))}
        </blockquote>
      );
      return;
    }

    blocos.push(
      <p key={i} className="my-4 leading-7 text-tinta/80">
        {inline(t)}
      </p>
    );
  });

  fecharLista("ul-fim");

  return <Fragment>{blocos}</Fragment>;
}
