# Portal BDFlow — Owner/Manager V2.1.1 (upload manual)

**Repositório:** https://github.com/JulianOHayashi/site
**Commit-base:** `7738350395e2e327aadb9584e04f318211c3cb60`
**Natureza:** V2.1 + correção pontual V2.1.1. Nada foi commitado, enviado ou implantado.

## O que mudou da V2.1 para a V2.1.1 (a correção)
**Bug corrigido:** no `PortalLogin`, o efeito que faz a troca de conta chamava
`supabase.auth.signOut({ scope: "local" })` **duas vezes** para uma única troca,
porque o app é montado com `React.StrictMode` (dev), que executa efeitos
montar→desmontar→remontar. Os 37 testes da V2.1 não cobriam esse caso.

**Correção:** um guard de idempotência (`useRef`) impede a segunda execução
automática do encerramento. A **retentativa manual** ("Tentar encerrar sessão
novamente") reseta o guard explicitamente e continua funcionando; em caso de
falha do `signOut`, o guard também é liberado para permitir nova tentativa.
Arquivo alterado: `src/pages/portal/PortalLogin.tsx`.

**Teste novo:** `src/test/ui/troca-conta-strictmode.test.tsx` — renderiza sob
`<StrictMode>` e prova `signOut` chamado **exatamente 1 vez**; e que, após falha,
a retentativa manual chama `signOut` novamente (2 no total). Antes da correção o
teste falhava com "esperado 1, recebido 2".

## Comparação com a `main` atual
A `main` do repositório permanece em `7738350` (não avançou). Upload por arrastar
é seguro sobre a main atual — sem conflitos.

## Resultados desta execução (worktree final limpo)
- `npm run typecheck` → exit 0
- `npm run build` → exit 0
- `npm test -- --run` → **39 testes de interface, 10 arquivos, 0 falhas** (37 da V2.1 + 2 do StrictMode)
- `git diff --check` → exit 0
- esbuild/node comercial → **62 PASS / 0 FAIL**
- esbuild/node portal (puro) → **133 PASS / 0 FAIL**
- Patch consolidado reaplicado em clone independente do commit-base → OK

## Estado V2/V2.1 preservado
Redirect `/portal/cadastro`→`/parceiros/cadastro`; modal de revogação sem senha
(motivo + REVOGAR, prova opaca); convites com `batchId`, resumo por lote,
revogação de disponíveis do lote e "Gerar substituto"; suspender/reativar/revogar
por status; `archived` com "Vínculo encerrado"; `INVITATION_EMAIL_MISMATCH`→
`email_divergente`; quantidade grande com inteiro seguro + rótulos esparsos +
páginas de 20; "Trocar de conta" com `switch_account=1`, `signOut({scope:"local"})`,
retorno ao `next` só após nova auth, `next` validado (rejeita `/portal-malicioso`,
`/portal.example`, externos). Formação 24/12/12/12/12/12 = 84 intocada.

## Limitação de inspeção visual
Não há navegador interativo neste ambiente. A verificação foi por testes reais de
render/interação/teclado (Vitest/RTL/jsdom), incluindo agora o caso StrictMode.
Build e jsdom não comprovam o visual final; valide no preview da Vercel.

## Continua dependendo de backend
Convites, filiais, capacidades, validação e a prova opaca de ação sensível
permanecem `BACKEND_NOT_AVAILABLE` — nada declarado funcional.

---

## Upload manual no GitHub
1. Abra **JulianOHayashi/site**.
2. Crie e selecione a branch **`portal-owner-manager-v2.1`** (ou `-v2.1.1`).
3. **Confirme que a branch NÃO é `main`.**
4. Extraia este ZIP.
5. Abra **`PARA_ENVIAR_AO_GITHUB`**.
6. Arraste **o conteúdo** dessa pasta, preservando os caminhos.
7. **Não** envie o ZIP, o handoff, o `.patch`, o `MANIFESTO` nem os `SHA256SUMS`.
8. Mensagem: **`Implement owner and manager portal separation V2.1`**.
9. Reconfirme a branch antes de "Commit changes".
10. Aguarde o preview da Vercel e teste antes de qualquer merge.

### Exclusões
Nenhuma (0). O upload por arrastar adiciona/atualiza, não remove — nenhuma ação extra.
