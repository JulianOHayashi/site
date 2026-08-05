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
import PortalCadastro from "./pages/portal/PortalCadastro";
import PortalValidar from "./pages/portal/PortalValidar";
import PortalSolicitacoes from "./pages/portal/PortalSolicitacoes";
import SelecionarLocalidade from "./pages/SelecionarLocalidade";
import Oportunidades from "./pages/Oportunidades";
import OportunidadeDetalhe from "./pages/OportunidadeDetalhe";
import CommercialTerritoryGuard from "./components/CommercialTerritoryGuard";

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
        <Route path="/parceiros" element={<Parceiros />} />
        <Route path="/parceiros/painel" element={<ParceirosPainel />} />
        {/* Portal do parceiro BDFlow (Supabase do Site). */}
        <Route path="/portal" element={<Navigate to="/portal/login" replace />} />
        <Route path="/portal/login" element={<PortalLogin />} />
        <Route path="/portal/dashboard" element={<PortalGuard><PortalDashboard /></PortalGuard>} />
        <Route path="/portal/cadastro" element={<PortalGuard><PortalCadastro /></PortalGuard>} />
        <Route path="/portal/validar" element={<PortalGuard><PortalValidar /></PortalGuard>} />
        <Route path="/portal/solicitacoes" element={<PortalGuard><PortalSolicitacoes /></PortalGuard>} />
        {/* Compatibilidade temporária do antigo endereço do painel. */}
        <Route path="/portal/painel" element={<Navigate to="/portal/dashboard" replace />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
