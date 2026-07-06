import { Link } from "react-router-dom";

export default function Header() {
  return (
    <header className="border-b border-borda bg-papel/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        <Link to="/" className="display text-xl">
          camisas<span className="text-magenta">.</span>es
        </Link>
        <nav className="flex items-center gap-5 text-sm font-medium">
          <Link to="/produtos" className="hover:text-magenta">
            Modelos
          </Link>
          <Link to="/admin" className="text-tinta/50 hover:text-tinta">
            Admin
          </Link>
        </nav>
      </div>
    </header>
  );
}
