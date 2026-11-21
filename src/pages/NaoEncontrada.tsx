import { Link } from "react-router-dom";

/**
 * Endereço inexistente ou removido (inclui as URLs da antiga loja de camisas,
 * sem conteúdo equivalente). Em produção o servidor entrega esta tela com
 * HTTP 404 (dist/404.html) e noindex; aqui só a mensagem. Mesmo visual da
 * tela "Em breve".
 */
export default function NaoEncontrada() {
  return (
    <main className="flex min-h-[70vh] flex-col items-center justify-center px-4 text-center">
      <h1 className="text-4xl sm:text-6xl">
        Página não encontrada
        <span className="mx-auto mt-3 traco-marca w-20" />
      </h1>
      <p className="mt-6 max-w-md text-tinta/70">
        O endereço acessado não existe ou foi removido.
      </p>
      <Link to="/" className="btn-secondary mt-8">
        Voltar ao início
      </Link>
    </main>
  );
}
