import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import EmBreve from "./pages/EmBreve";
import Admin from "./pages/Admin";
import AdminLogin from "./pages/AdminLogin";
import AdminGuard from "./components/AdminGuard";
import PortalGuard from "./components/PortalGuard";
import Parceiros from "./pages/Parceiros";
import ParceirosPainel from "./pages/ParceirosPainel";
import PortalLogin from "./pages/portal/PortalLogin";
import PortalDashboard from "./pages/portal/PortalDashboard";
import PortalValidar from "./pages/portal/PortalValidar";
import PortalSolicitacoes from "./pages/portal/PortalSolicitacoes";
import SelecionarLocalidade from "./pages/SelecionarLocalidade";
import Oportunidades from "./pages/Oportunidades";
import OportunidadeDetalhe from "./pages/OportunidadeDetalhe";
import CommercialTerritoryGuard from "./components/CommercialTerritoryGuard";
import ParceirosCadastro from "./pages/parceiros/ParceirosCadastro";
import ConfirmarEmail from "./pages/parceiros/ConfirmarEmail";
import RecuperarAcesso from "./pages/parceiros/RecuperarAcesso";
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
        <Route path="/checkout" element={<Navigate to="/oportunidades" replace />} />

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
        <Route path="/parceiros/painel" element={<ParceirosPainel />} />
        {/* Onboarding Fase 2A: solicitação empresarial pré-Auth. */}
        <Route path="/parceiros/cadastro" element={<ParceirosCadastro />} />
        <Route path="/parceiros/confirmar" element={<ConfirmarEmail />} />
        <Route path="/parceiros/recuperar" element={<RecuperarAcesso />} />
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
        <Route path="/portal/dashboard" element={<PortalGuard><PortalDashboard /></PortalGuard>} />
        {/* Cadastro legado neutralizado: redirect seguro, sem RPC legada. */}
        <Route path="/portal/cadastro" element={<Navigate to="/parceiros/cadastro" replace />} />
        <Route path="/portal/validar" element={<PortalGuard><PortalValidar /></PortalGuard>} />
        <Route path="/portal/solicitacoes" element={<PortalGuard><PortalSolicitacoes /></PortalGuard>} />
        {/* Compatibilidade temporária do antigo endereço do painel. */}
        <Route path="/portal/painel" element={<Navigate to="/portal/dashboard" replace />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
