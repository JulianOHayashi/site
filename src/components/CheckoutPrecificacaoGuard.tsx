import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { fetchPublicPricing } from "../services/commercialService";
import { permiteCheckoutSF15 } from "../domain/pricing/pricingGateSF15";

/**
 * Nunca libera checkout com regra histórica quando os preços da vitrine
 * apresentam a proposta SF-v1.5. Deixa o próprio backend decidir as cobranças.
 */
export default function CheckoutPrecificacaoGuard({children}:{children:ReactNode}) {
  const [autorizado,setAutorizado]=useState(false);
  useEffect(() => {
    let live=true;
    fetchPublicPricing()
      .then((precos)=>{ if(live) setAutorizado(permiteCheckoutSF15(precos)); })
      .catch(()=>{ if(live) setAutorizado(false); });
    return ()=>{live=false};
  },[]);
  if(!autorizado) return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <div className="card p-6" role="status">
        <h1 className="text-2xl font-bold">Contratação em atualização</h1>
        <p className="mt-3 text-tinta/70">
          As condições comerciais estão sendo atualizadas. Não é possível
          reservar ou contratar pelo preço antigo. Consulte as propostas
          individuais na página de oportunidades.
        </p>
        <a className="btn-secondary mt-5 inline-block" href="/oportunidades">Ver oportunidades</a>
      </div>
    </main>
  );
  return <>{children}</>;
}
