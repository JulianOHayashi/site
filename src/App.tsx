import { BrowserRouter, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import HomeClassica from "./pages/HomeClassica";
import EmBreve from "./pages/EmBreve";
import Produtos from "./pages/Produtos";
import ProdutoDetalhe from "./pages/ProdutoDetalhe";
import Personalizar from "./pages/Personalizar";
import Checkout from "./pages/Checkout";
import Admin from "./pages/Admin";
import Parceiros from "./pages/Parceiros";
import ParceirosPainel from "./pages/ParceirosPainel";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        {/* Cópia de segurança de versão anterior do site */}
        <Route path="/classica" element={<HomeClassica />} />
        <Route path="/em-breve" element={<EmBreve />} />
        <Route path="/produtos" element={<Produtos />} />
        <Route path="/produto/:slug" element={<ProdutoDetalhe />} />
        <Route path="/personalizar/:slug" element={<Personalizar />} />
        <Route path="/checkout" element={<Checkout />} />
        <Route path="/admin" element={<Admin />} />
        {/* Área de parceiros (login/cadastro + painel protegido) */}
        <Route path="/parceiros" element={<Parceiros />} />
        <Route path="/parceiros/painel" element={<ParceirosPainel />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
