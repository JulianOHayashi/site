import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import EmBreve from "./pages/EmBreve";
import RevisaoContratacao from "./pages/RevisaoContratacao";
import Admin from "./pages/Admin";
import AdminLogin from "./pages/AdminLogin";
import AdminGuard from "./components/AdminGuard";
import PortalGuard from "./components/PortalGuard";
import Parceiros from "./pages/Parceiros";
import ParceirosAcesso from "./pages/ParceirosAcesso";
import PortalLogin from "./pages/portal/PortalLogin";
import PortalForgotPassword from "./pages/portal/PortalForgotPassword";
import PortalResetPassword from "./pages/portal/PortalResetPassword";
import PortalDashboard from "./pages/portal/PortalDashboard";
import PortalEquipe from "./pages/portal/PortalEquipe";
import PortalValidar from "./pages/portal/PortalValidar";
import BeneficiosValidar from "./pages/beneficios/BeneficiosValidar";
// A captura do fragmento roda no IMPORT, antes de qualquer rota montar:
// o guard de autenticacao pode navegar, e o fragmento nao sobrevive a
// navegacao — a memoria do modulo sobrevive.
import { capturarFragmento } from "./lib/benefitTokenFragment";

capturarFragmento();
import PortalSolicitacoes from "./pages/portal/PortalSolicitacoes";
import SelecionarLocalidade from "./pages/SelecionarLocalidade";
import Oportunidades from "./pages/Oportunidades";
import OportunidadeDetalhe from "./pages/OportunidadeDetalhe";
import CommercialTerritoryGuard from "./components/CommercialTerritoryGuard";
import ParceirosCadastro from "./pages/parceiros/ParceirosCadastro";
import ConfirmarEmail from "./pages/parceiros/ConfirmarEmail";
import RecuperarAcesso from "./pages/parceiros/RecuperarAcesso";
import AceitarConviteManager from "./pages/parceiros/AceitarConviteManager";
import SolicitacaoStatus from "./pages/parceiros/SolicitacaoStatus";
import ProvisionalGuard from "./components/ProvisionalGuard";
import AdminSolicitacoes from "./pages/admin/AdminSolicitacoes";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Domínio público e comercial vigente. */}
        <Route path="/" element={<Home />} />
        <Route path="/selecionar-localidade" element={<SelecionarLocalidade />} />
        <Route
          path="/oportunidades"
          element={
            <CommercialTerritoryGuard>
              <Oportunidades />
            </CommercialTerritoryGuard>
          }
        />
        <Route
          path="/oportunidades/:nicheSlug"
          element={
            <CommercialTerritoryGuard>
              <OportunidadeDetalhe />
            </CommercialTerritoryGuard>
          }
        />
        <Route path="/em-breve" element={<EmBreve />} />

        {/* Compatibilidade temporária para links da antiga loja. */}
        <Route path="/selecionar-estado" element={<Navigate to="/selecionar-localidade" replace />} />
        <Route path="/classica" element={<Navigate to="/" replace />} />
        <Route path="/produtos" element={<Navigate to="/oportunidades" replace />} />
        <Route path="/produto/:slug" element={<Navigate to="/oportunidades" replace />} />
        <Route path="/personalizar/:slug" element={<Navigate to="/oportunidades" replace />} />
        {/* Comercial V2: revisão pública da tabela vigente. Não cria pedido,
            não escolhe fidelidade nem trilho, não aceita valor por URL. */}
        <Route
          path="/checkout"
          element={
            <CommercialTerritoryGuard>
              <RevisaoContratacao />
            </CommercialTerritoryGuard>
          }
        />

        <Route path="/admin/login" element={<AdminLogin />} />
        <Route
          path="/admin"
          element={
            <AdminGuard>
              <Admin />
            </AdminGuard>
          }
        />
        <Route
          path="/admin/solicitacoes"
          element={
            <AdminGuard>
              <AdminSolicitacoes />
            </AdminGuard>
          }
        />
        <Route path="/parceiros" element={<Parceiros />} />
        <Route path="/parceiros/acesso" element={<ParceirosAcesso />} />
        <Route path="/parceiros/painel" element={<Navigate to="/portal/dashboard" replace />} />
        {/* Onboarding Fase 2A: solicitação empresarial pré-Auth. */}
        <Route path="/parceiros/cadastro" element={<ParceirosCadastro />} />
        <Route path="/parceiros/confirmar" element={<ConfirmarEmail />} />
        <Route path="/parceiros/recuperar" element={<RecuperarAcesso />} />
        <Route path="/parceiros/convite" element={<AceitarConviteManager />} />
        <Route
          path="/parceiros/solicitacao"
          element={
            <ProvisionalGuard>
              <SolicitacaoStatus />
            </ProvisionalGuard>
          }
        />
        {/* Portal do parceiro BDFlow (Supabase do Site). */}
        <Route path="/portal" element={<Navigate to="/portal/login" replace />} />
        <Route path="/portal/login" element={<PortalLogin />} />
        <Route path="/portal/recuperar-senha" element={<PortalForgotPassword />} />
        <Route path="/portal/redefinir-senha" element={<PortalResetPassword />} />
        <Route path="/portal/dashboard" element={<PortalGuard><PortalDashboard /></PortalGuard>} />
        <Route path="/portal/equipe" element={<PortalGuard><PortalEquipe /></PortalGuard>} />
        {/* Cadastro legado neutralizado: redirect seguro, sem RPC legada. */}
        <Route path="/portal/cadastro" element={<Navigate to="/parceiros/cadastro" replace />} />
        <Route path="/portal/validar" element={<PortalGuard><PortalValidar /></PortalGuard>} />
        <Route path="/beneficios/validar/:publicLookupId" element={<PortalGuard><BeneficiosValidar /></PortalGuard>} />
        <Route path="/portal/solicitacoes" element={<PortalGuard><PortalSolicitacoes /></PortalGuard>} />
        {/* Compatibilidade temporária do antigo endereço do painel. */}
        <Route path="/portal/painel" element={<Navigate to="/portal/dashboard" replace />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
