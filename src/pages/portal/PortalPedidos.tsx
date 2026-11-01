import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import { EmpresaAtualBarra, EmpresaPortao } from "../../portal/EmpresaSeletor";
import { listarPedidosDaEmpresa, type PedidoResumo } from "../../services/customizationImageService";

/**
 * /portal/pedidos — pedidos de exclusividade da empresa ativa.
 *
 * Só o responsável (partner_owner ativo) vê esta lista: o próprio servidor
 * devolve o bloco comercial apenas para owner/admin. O manager recebe uma
 * explicação, sem dado nem ação comercial.
 *
 * O selo "Imagem registrada / pendente" é só informativo; ele não afirma
 * nada sobre formação do grupo, que depende de outras condições do servidor.
 */
export default function PortalPedidos() {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Pedidos" />
        <EmpresaAtualBarra />
        <EmpresaPortao semVinculo={<SemAcesso />}>
          {({ companyId, papel, geracao }) =>
            papel === "partner_owner" ? (
              <ListaOwner key={`${companyId}:${geracao}`} companyId={companyId} />
            ) : (
              <SemAcesso />
            )
          }
        </EmpresaPortao>
      </main>
    </>
  );
}

export function SemAcesso() {
  return (
    <section className="mt-8 rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
      <h2 className="text-xl font-bold">Área do responsável pela empresa</h2>
      <p className="mt-3 leading-7 text-tinta/75">
        Os pedidos de exclusividade e a imagem para personalização ficam
        disponíveis apenas para o responsável pela empresa.
      </p>
      <Link to="/portal/dashboard" className="btn-secondary mt-6 inline-flex">
        Voltar ao painel
      </Link>
    </section>
  );
}

type Estado =
  | { fase: "carregando" }
  | { fase: "erro" }
  | { fase: "sem_acesso" }
  | { fase: "ok"; pedidos: PedidoResumo[] };

function ListaOwner({ companyId }: { companyId: string }) {
  const empresa = useEmpresaSelecionada();
  const ativo = empresa.fase === "pronta" && empresa.atual.member_status === "active";
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });

  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    listarPedidosDaEmpresa(companyId).then((r) => {
      if (!vivo) return;
      if (r.tipo === "ok") setEstado({ fase: "ok", pedidos: r.pedidos });
      else if (r.tipo === "sem_acesso") setEstado({ fase: "sem_acesso" });
      else setEstado({ fase: "erro" });
    });
    return () => {
      vivo = false;
    };
  }, [companyId, ativo]);

  if (!ativo || estado.fase === "sem_acesso") return <SemAcesso />;
  if (estado.fase === "carregando") {
    return (
      <p role="status" className="mt-10 text-center text-sm text-tinta/60">
        Carregando pedidos...
      </p>
    );
  }
  if (estado.fase === "erro") {
    return (
      <p role="alert" className="aviso-erro mt-8 p-4">
        Não foi possível carregar os pedidos agora. Tente novamente em instantes.
      </p>
    );
  }
  if (estado.pedidos.length === 0) {
    return (
      <section className="mt-8 rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
        <h2 className="text-xl font-bold">Nenhum pedido de exclusividade</h2>
        <p className="mt-3 leading-7 text-tinta/75">
          Quando a empresa concluir a contratação de uma exclusividade, o pedido
          aparece aqui para o envio da imagem para personalização.
        </p>
      </section>
    );
  }

  return (
    <ul className="mt-8 space-y-4" aria-label="Pedidos de exclusividade">
      {estado.pedidos.map((p) => (
        <li
          key={p.orderId}
          className="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-borda bg-superficie p-5"
        >
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
              Pedido de exclusividade
            </p>
            <h2 className="mt-1 text-lg font-bold">{p.nicho}</h2>
            <SeloImagem registrada={p.temImagem} />
          </div>
          <Link
            to={`/portal/pedidos/${encodeURIComponent(p.orderId)}/personalizacao`}
            className="btn-primary"
          >
            Imagem para personalização
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function SeloImagem({ registrada }: { registrada: boolean }) {
  return (
    <span
      className={`mt-2 inline-block rounded-full px-3 py-1 text-xs font-semibold ${
        registrada ? "bg-verde/10 text-verde" : "bg-amarelo/10 text-amarelo"
      }`}
    >
      {registrada ? "Imagem registrada" : "Imagem pendente"}
    </span>
  );
}
