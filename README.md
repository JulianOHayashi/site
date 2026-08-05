# BDFlow Site

Site público, comercial e administrativo da BDFlow. O projeto organiza
oportunidades por região e nicho, autenticação de parceiros e a fundação do
Portal BDFlow.

## Stack

- React 18, Vite e TypeScript
- Tailwind CSS
- Supabase do Site
- Vercel

## Execução local

```bash
npm ci
npm run dev
```

Variáveis públicas esperadas:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

Nunca coloque `service_role`, senhas ou chaves privadas no frontend.

## Rotas vigentes

- `/`: apresentação pública BDFlow
- `/selecionar-localidade`: seleção de UF e cidade
- `/oportunidades`: formação comercial por região e nicho
- `/parceiros`: autenticação e área comercial de parceiros
- `/portal`: autenticação e operação do Portal BDFlow
- `/admin`: área administrativa protegida

Endereços antigos da loja redirecionam temporariamente para o domínio atual;
o código de camisas, produtos, estoque e checkout antigo não integra mais o
projeto.

## Regras comerciais já consolidadas

- formação de referência: 84 unidades;
- supermercado: 24 unidades;
- farmácia, roupas femininas, roupas masculinas, calçados femininos e calçados
  masculinos: 12 unidades cada;
- o nicho é contratado integralmente;
- não existe desconto progressivo por quantidade;
- o ciclo comercial do Site é separado do ciclo operacional do App.

## Validação

```bash
npm run validate
```

Esse comando procura resíduos proibidos, executa o typecheck e gera o build de
produção.

## Documentação

Comece por [`docs/00-ESTADO-ATUAL-BDFLOW.md`](docs/00-ESTADO-ATUAL-BDFLOW.md).
Os demais documentos registram especificações, migrations e verificações
técnicas; nenhum arquivo SQL deve ser executado apenas por existir no
repositório.
