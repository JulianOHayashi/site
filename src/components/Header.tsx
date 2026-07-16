import SiteHeader from "./SiteHeader";

/**
 * Header — mantido por compatibilidade: todas as páginas internas
 * que importam <Header /> passam a exibir a navegação moderna.
 */
export default function Header() {
  return <SiteHeader />;
}
