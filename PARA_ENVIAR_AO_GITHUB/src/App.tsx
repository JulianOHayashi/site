import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import HomeClassica from "./pages/HomeClassica";
import EmBreve from "./pages/EmBreve";
import Produtos from "./pages/Produtos";
import ProdutoDetalhe from "./pages/ProdutoDetalhe";
import Personalizar from "./pages/Personalizar";
import Checkout from "./pages/Checkout";
import Admin from "./pages/Admin";
import AdminLogin from "./pages/AdminLogin";
import AdminGuard from "./components/AdminGuard";
import PortalGuard from "./components/PortalGuard";
import Parceiros from "./pages/Parceiros";
import ParceirosPainel from "./pages/ParceirosPainel";
import ParceirosCadastro from "./pages/ParceirosCadastro";
import PortalLogin from "./pages/portal/PortalLogin";
import PortalDashboard from "./pages/portal/PortalDashboard";
import PortalCadastroRedirect from "./pages/portal/PortalCadastroRedirect";
import SelecionarEstado from "./pages/SelecionarEstado";
import EstadoGuard from "./components/EstadoGuard";
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
        {/* Home pública BDFlow — NÃO exige o território legado de camisas. */}
        <Route path="/" element={<Home />} />
        <Route path="/selecionar-estado" element={<SelecionarEstado />} />

        {/* Fase 1 — domínio comercial BDFlow */}
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
        {/* Cópia de segurança de versão anterior do site */}
        <Route path="/classica" element={<HomeClassica />} />
        <Route path="/em-breve" element={<EmBreve />} />
        {/* Comércio do site (Supabase do SITE) */}
        <Route path="/produtos" element={<EstadoGuard><Produtos /></EstadoGuard>} />
        <Route path="/produto/:slug" element={<EstadoGuard><ProdutoDetalhe /></EstadoGuard>} />
        <Route path="/personalizar/:slug" element={<EstadoGuard><Personalizar /></EstadoGuard>} />
        <Route path="/checkout" element={<EstadoGuard><Checkout /></EstadoGuard>} />
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
        <Route path="/parceiros/cadastro" element={<ParceirosCadastro />} />
        <Route path="/parceiros/painel" element={<ParceirosPainel />} />
        {/* Portal do parceiro BDFlow (Supabase do SITE — auth por sessão) */}
        <Route path="/portal" element={<Navigate to="/portal/login" replace />} />
        <Route path="/portal/login" element={<PortalLogin />} />
        <Route path="/portal/dashboard" element={<PortalGuard><PortalDashboard /></PortalGuard>} />
        {/* /portal/cadastro: redirect incondicional — RPC antiga fora do caminho público (Pacote P0) */}
        <Route path="/portal/cadastro" element={<PortalCadastroRedirect />} />
        <Route path="/portal/validar" element={<PortalGuard><PortalValidar /></PortalGuard>} />
        <Route path="/portal/solicitacoes" element={<PortalGuard><PortalSolicitacoes /></PortalGuard>} />
        {/* rota antiga do portal */}
        <Route path="/portal/painel" element={<Navigate to="/portal/dashboard" replace />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
