import { BrowserRouter, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import HomeClassica from "./pages/HomeClassica";
import EmBreve from "./pages/EmBreve";
import Produtos from "./pages/Produtos";
import ProdutoDetalhe from "./pages/ProdutoDetalhe";
import Personalizar from "./pages/Personalizar";
import Checkout from "./pages/Checkout";
import Admin from "./pages/Admin";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        {/* Cópia de segurança da versão anterior do site */}
        <Route path="/classica" element={<HomeClassica />} />
        <Route path="/em-breve" element={<EmBreve />} />
        <Route path="/produtos" element={<Produtos />} />
        <Route path="/produto/:slug" element={<ProdutoDetalhe />} />
        <Route path="/personalizar/:slug" element={<Personalizar />} />
        <Route path="/checkout" element={<Checkout />} />
        <Route path="/admin" element={<Admin />} />
        <Route path="*" element={<EmBreve />} />
      </Routes>
    </BrowserRouter>
  );
}
