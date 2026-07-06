import { Link, useLocation } from "react-router-dom";

export default function EmBreve() {
  const { state } = useLocation() as {
    state?: { estado?: string; origem?: string };
  };
  const individual = state?.origem === "individual";

  return (
    <main className="flex min-h-[70vh] flex-col items-center justify-center px-4 text-center">
      <h1 className="text-4xl sm:text-6xl">
        Em breve por aqui
        <span className="mx-auto mt-3 block h-2 w-40 rounded-full bg-amarelo" />
      </h1>
      <p className="mt-6 max-w-md text-tinta/70">
        {individual
          ? "O lado Individual está em construção. Enquanto isso, o lado Empresarial já está no ar para o Espírito Santo."
          : state?.estado
            ? `Estamos começando pelo Espírito Santo. Logo chegamos a ${state.estado}!`
            : "Estamos começando pelo Espírito Santo. Logo chegamos ao seu estado."}
      </p>
      <Link to="/" className="btn-secondary mt-8">
        Voltar ao início
      </Link>
    </main>
  );
}
