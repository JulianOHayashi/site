import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo, dataBr } from "./portalUi";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import { EmpresaAtualBarra, EmpresaPortao } from "../../portal/EmpresaSeletor";
import { SeloImagem, SemAcesso } from "./PortalPedidos";
import {
  ACCEPT_ATTR,
  MENSAGEM_ARQUIVO,
  enviarImagemPersonalizacao,
  listarPedidosDaEmpresa,
  mensagemDeMotivo,
  obterImagemAtual,
  tamanhoLegivel,
  validarArquivo,
  type ImagemAtual,
  type PedidoResumo,
} from "../../services/customizationImageService";

/**
 * /portal/pedidos/:orderId/personalizacao — imagem para personalização.
 *
 * O pedido só é mostrado se estiver na lista comercial da empresa ATIVA
 * (devolvida pelo servidor apenas ao owner). Isso evita oferecer envio para
 * um pedido de outra empresa; mesmo assim, quem decide é o servidor, que
 * recusa qualquer envio fora das regras.
 */
export default function PortalPedidoPersonalizacao() {
  const { orderId = "" } = useParams();
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Imagem para personalização" />
        <EmpresaAtualBarra />
        <EmpresaPortao semVinculo={<SemAcesso />}>
          {({ companyId, papel, geracao }) =>
            papel === "partner_owner" ? (
              <Personalizacao
                key={`${companyId}:${geracao}:${orderId}`}
                companyId={companyId}
                orderId={orderId}
              />
            ) : (
              <SemAcesso />
            )
          }
        </EmpresaPortao>
      </main>
    </>
  );
}

type Carga =
  | { fase: "carregando" }
  | { fase: "erro" }
  | { fase: "sem_acesso" }
  | { fase: "nao_encontrado" }
  | { fase: "ok"; pedido: PedidoResumo; imagem: ImagemAtual | null; imagemErro: boolean };

type Envio =
  | { fase: "parado" }
  | { fase: "enviando" }
  | { fase: "sucesso" }
  | { fase: "erro"; mensagem: string };

function Personalizacao({ companyId, orderId }: { companyId: string; orderId: string }) {
  const empresa = useEmpresaSelecionada();
  const ativo = empresa.fase === "pronta" && empresa.atual.member_status === "active";
  const [carga, setCarga] = useState<Carga>({ fase: "carregando" });
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [erroArquivo, setErroArquivo] = useState<string | null>(null);
  const [envio, setEnvio] = useState<Envio>({ fase: "parado" });
  const inputRef = useRef<HTMLInputElement | null>(null);
  const vivo = useRef(true);

  useEffect(() => {
    vivo.current = true;
    return () => {
      vivo.current = false;
    };
  }, []);

  const carregar = useCallback(async () => {
    const lista = await listarPedidosDaEmpresa(companyId);
    if (!vivo.current) return;
    if (lista.tipo === "sem_acesso") return setCarga({ fase: "sem_acesso" });
    if (lista.tipo === "erro") return setCarga({ fase: "erro" });
    const pedido = lista.pedidos.find((p) => p.orderId === orderId);
    if (!pedido) return setCarga({ fase: "nao_encontrado" });
    const atual = await obterImagemAtual(orderId);
    if (!vivo.current) return;
    setCarga({
      fase: "ok",
      // A leitura direta é mais recente que o resumo quando acabou de haver envio.
      pedido: { ...pedido, temImagem: pedido.temImagem || atual.tipo === "ok" },
      imagem: atual.tipo === "ok" ? atual.imagem : null,
      imagemErro: atual.tipo === "erro",
    });
  }, [companyId, orderId]);

  useEffect(() => {
    if (ativo) void carregar();
  }, [ativo, carregar]);

  // Preview local: URL de objeto liberada ao trocar de arquivo e ao sair.
  useEffect(() => {
    if (!arquivo) {
      setPreview(null);
      return;
    }
    const url = URL.createObjectURL(arquivo);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [arquivo]);

  const escolher = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0] ?? null;
    setEnvio({ fase: "parado" });
    if (!f) {
      setArquivo(null);
      setErroArquivo(null);
      return;
    }
    const v = validarArquivo(f);
    if (!v.ok) {
      setArquivo(null);
      setErroArquivo(MENSAGEM_ARQUIVO[v.erro]);
      if (inputRef.current) inputRef.current.value = "";
      return;
    }
    setErroArquivo(null);
    setArquivo(f);
  };

  const enviar = async () => {
    if (!arquivo || envio.fase === "enviando") return;
    setEnvio({ fase: "enviando" });
    const r = await enviarImagemPersonalizacao(orderId, arquivo);
    if (!vivo.current) return;
    if (r.tipo === "erro") {
      setEnvio({ fase: "erro", mensagem: mensagemDeMotivo(r.motivo) });
      return;
    }
    setArquivo(null);
    if (inputRef.current) inputRef.current.value = "";
    setEnvio({ fase: "sucesso" });
    await carregar();
  };

  if (!ativo || carga.fase === "sem_acesso") return <SemAcesso />;
  if (carga.fase === "carregando") {
    return (
      <p role="status" className="mt-10 text-center text-sm text-tinta/60">
        Carregando pedido...
      </p>
    );
  }
  if (carga.fase === "erro") {
    return (
      <p role="alert" className="aviso-erro mt-8 p-4">
        Não foi possível carregar o pedido agora. Tente novamente em instantes.
      </p>
    );
  }
  if (carga.fase === "nao_encontrado") {
    return (
      <section className="mt-8 rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
        <h2 className="text-xl font-bold">Pedido não encontrado</h2>
        <p className="mt-3 leading-7 text-tinta/75">
          Este pedido não está entre os pedidos ativos da empresa selecionada.
        </p>
        <Link to="/portal/pedidos" className="btn-secondary mt-6 inline-flex">
          Ver pedidos
        </Link>
      </section>
    );
  }

  const { pedido, imagem, imagemErro } = carga;
  const existe = pedido.temImagem;
  const enviando = envio.fase === "enviando";

  return (
    <div className="mt-8 space-y-6">
      <section
        aria-labelledby="pedido-titulo"
        className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8"
      >
        <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
          Pedido de exclusividade
        </p>
        <h2 id="pedido-titulo" className="mt-1 text-xl font-bold">
          {pedido.nicho}
        </h2>
        <SeloImagem registrada={existe} />
      </section>

      <section
        aria-labelledby="atual-titulo"
        className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8"
      >
        <h2 id="atual-titulo" className="text-lg font-bold">
          Imagem atual
        </h2>
        {imagem ? (
          <figure className="mt-4">
            <img
              src={imagem.url}
              alt="Imagem atual para personalização"
              className="max-h-80 rounded-2xl border border-borda bg-superficie2 object-contain"
            />
            <figcaption className="mt-2 text-sm text-tinta/65">
              {tamanhoLegivel(imagem.byteSize)}
              {dataBr(imagem.registradaEm) ? ` · enviada em ${dataBr(imagem.registradaEm)}` : ""}
            </figcaption>
          </figure>
        ) : imagemErro ? (
          <p role="alert" className="mt-3 text-sm text-tinta/75">
            Não foi possível exibir a imagem atual agora. Recarregue a página para tentar de novo.
          </p>
        ) : (
          <p className="mt-3 text-sm text-tinta/75">Nenhuma imagem enviada para este pedido ainda.</p>
        )}
      </section>

      <section
        aria-labelledby="envio-titulo"
        className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8"
      >
        <h2 id="envio-titulo" className="text-lg font-bold">
          Imagem para personalização
        </h2>
        <p className="mt-2 leading-7 text-tinta/75">
          Envie a arte ou imagem que será usada como referência na personalização.
          Formatos aceitos: JPG, PNG ou WebP. Tamanho máximo: 10 MB.
        </p>
        {existe && (
          <p className="mt-2 text-sm text-tinta/65">
            Uma nova imagem substitui a atual neste pedido. As versões anteriores
            ficam guardadas no histórico.
          </p>
        )}

        <label htmlFor="arquivo-personalizacao" className="mt-5 block text-sm font-semibold">
          {existe ? "Escolher nova imagem" : "Escolher imagem"}
        </label>
        <input
          id="arquivo-personalizacao"
          ref={inputRef}
          type="file"
          accept={ACCEPT_ATTR}
          onChange={escolher}
          disabled={enviando}
          className="mt-2 block w-full text-sm"
        />

        {erroArquivo && (
          <p role="alert" className="aviso-erro mt-3 p-3 text-sm">
            {erroArquivo}
          </p>
        )}

        {arquivo && preview && (
          <figure className="mt-5">
            <img
              src={preview}
              alt="Pré-visualização da imagem escolhida"
              className="max-h-80 rounded-2xl border border-borda bg-superficie2 object-contain"
            />
            <figcaption className="mt-2 text-sm text-tinta/65">
              <span className="font-semibold text-tinta">{arquivo.name}</span>
              {" · "}
              {tamanhoLegivel(arquivo.size)}
            </figcaption>
          </figure>
        )}

        <button
          type="button"
          onClick={enviar}
          disabled={!arquivo || enviando}
          className="btn-primary mt-5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {enviando ? "Enviando..." : existe ? "Substituir imagem" : "Enviar imagem"}
        </button>

        <div aria-live="polite">
          {envio.fase === "sucesso" && (
            <p role="status" className="aviso-ok mt-4 p-3 text-sm">
              Imagem enviada e registrada para este pedido.
            </p>
          )}
          {envio.fase === "erro" && (
            <p role="alert" className="aviso-erro mt-4 p-3 text-sm">
              {envio.mensagem}
            </p>
          )}
        </div>
      </section>

      <Link to="/portal/pedidos" className="btn-secondary inline-flex">
        Voltar aos pedidos
      </Link>
    </div>
  );
}
