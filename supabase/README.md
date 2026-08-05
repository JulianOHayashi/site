# Artefatos Supabase do Site

Os arquivos desta pasta são scripts temáticos e verificações. Eles não formam
uma sequência automática de migrations e não devem ser executados em lote.

## Classificação

| Arquivo | Finalidade |
|---|---|
| `commercial-foundation-v1.sql` | Fundação comercial de território, nichos, oportunidades e formação 84 |
| `site-partner-core.sql` | Transição cadastral anterior; ainda documenta a RPC usada pelo frontend, mas não é a arquitetura final da Fase 2A |
| `fase2a-marco1-foundation.sql` | Fundação transversal do Marco 1 |
| `fase2a-marco1-preflight.sql` | Verificação anterior à fundação |
| `fase2a-marco1-is-site-admin-hardening*.sql` | Hardening isolado e suas verificações |
| `fase2a-marco1-verificacao-pos-v14*.sql` | Verificação posterior somente leitura |

Os schemas da antiga loja de camisas, estoque, checkout e desconto progressivo
foram removidos da árvore atual. Objetos equivalentes podem continuar no banco
remoto até uma migration de desativação ser preparada e verificada.

Antes de qualquer alteração remota:

1. inventarie dependências e privilégios;
2. prepare uma migration específica;
3. execute advisors de segurança e desempenho;
4. valide o fluxo afetado;
5. registre uma verificação posterior.
