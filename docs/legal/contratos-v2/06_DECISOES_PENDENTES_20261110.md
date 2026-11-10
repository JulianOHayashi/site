# Quadro de decisões jurídicas e técnicas pendentes — Contratos V2

Data: 2026-11-10. Nenhuma decisão abaixo foi tomada. As alternativas apoiam a
avaliação e **não estão aprovadas**. A coluna "Bloqueia" diz o que fica
impedido enquanto a decisão não sair.

## Jurídicas (D-J)

| Código | Decisão | Alternativas | Bloqueia |
|---|---|---|---|
| D-J1 | Responsabilidade por incidentes: dano ao veículo, desprendimento, acidente, terceiros, furto | (a) SmallFlags, conforme D-N1; (b) fornecedor credenciado, por contrato próprio; (c) repartição por causa, com seguro (D-J5) | Publicação do Mestre e do instrumento |
| D-J2 | Licenças municipais e autorizações de trânsito: quem obtém e quem paga | (a) SmallFlags como empresa de publicidade; (b) custo repassado com aprovação prévia; (c) execução restrita a municípios com autorização confirmada | Publicação; início de operação por município |
| D-J3 | Efeito da interrupção sobre prazo e valores | (a) suspensão de prazo e compensação de período; (b) redução proporcional; (c) substituição de divulgador ou veículo | Publicação dos Termos e do instrumento |
| D-J4 | Atividade contratada para segmento autorizado e Outros | (a) catálogo próprio por classificação; (b) descrição versionada e com hash na aprovação do segmento | Liberação do D9 (segmento e Outros) |
| D-J5 | Seguros: apólice do divulgador, responsabilidade civil, contratante e cobertura | Parecer de corretora e jurídico | Publicação; operação |
| D-J6 | Natureza da relação com o divulgador (MEI) | Parecer trabalhista específico | Operação (instrumento do divulgador, fora do Site) |
| D-J7 | Forma de assinatura do Acordo Mestre | (a) aceite eletrônico autenticado; (b) assinatura eletrônica avançada ou qualificada; (c) presencial, com registro administrativo atual | Publicação do Mestre |
| D-J8 | A mudança de objeto exige reaceite? | Hoje não há aceite anterior. Decidir `is_material_change` para versões futuras | Publicação dos Termos |
| D-J9 | Qualificação completa da SmallFlags (razão social, CNPJ, endereço) e cláusulas gerais (foro, comunicações, LGPD) | Redação jurídica | Publicação |

## Negócio e operação (D-N)

| Código | Decisão | Alternativas | Bloqueia |
|---|---|---|---|
| D-N1 | Quem fabrica, instala, inspeciona, substitui e remove; quem paga | (a) SmallFlags fornece e coordena; (b) fornecedor credenciado; (c) divulgador, com checklist | D-J1, Anexo Técnico, instrumento |
| D-N2 | Evidências de prestação e acesso do anunciante | Fotos datadas, vistoria, check-ins no App, periodicidade. Exige contrato de integração Site × App | Cláusula de execução; integração |
| D-N3 | Alterações de arte: limite, prazo e custo | (a) uma arte por ciclo, extras pagos; (b) número incluso | Termos e instrumento (sem alterar o preço vigente) |
| D-N4 | Classes de veículo permitidas | Ver Matriz, seção A.4. Recomendação preliminar: só automóvel ou utilitário particular, até haver parecer | Anexo Técnico (E7) |

## Técnicas (D-T)

| Código | Decisão | Responsável | Bloqueia |
|---|---|---|---|
| D-T1 | Especificação técnica completa (E1–E12 do Anexo Técnico) | Responsável técnico habilitado | Aprovação em `commercial_advertising_specs`; emissão de qualquer instrumento V2 |
| D-T2 | Enquadramento regulatório do conjunto (acessório ou modificação; CSV) | Responsável técnico e jurídico de trânsito | D-T1; operação |

## Regulatórias por município (D-R)

| Código | Município | Pendência | Situação |
|---|---|---|---|
| D-R1 | Vitória | Confirmar se a Lei 5.954/2003 alcança anúncio em veículo; requerente; taxa | Consulta formal à SEDEC |
| D-R2 | Vila Velha | Texto vigente da Lei 3.130/1995; cobertura de veículo | Consulta formal |
| D-R3 | Serra | Lei 6.095/2024, art. 29 (alvará para veículos, requerido por empresa de publicidade); decreto regulamentador; qualificação da SmallFlags | Consulta formal e verificação societária |
| D-R4 | Cariacica | Lei de publicidade vigente (2016/2023); veículos de propaganda | Consulta formal |
| D-R5 | Viana | Código de Posturas; anúncio em veículo | Consulta formal |

## Já decidido (não reabrir sem nova decisão)

- 6 posições e 84 unidades (Supermercado 24; Farmácia, Roupas F/M, Calçados e
  Outros com 12).
- Supermercado nunca substituível.
- Segmento só depois de aprovação administrativa.
- Exclusividade por atividade efetiva (classificação).
- Preço, contraprestação, pool, QA e remuneração inalterados.
- Fidelização pela atividade efetiva, CNPJ e cidade.
- Provisionamento ao App bloqueado até o contrato v3.
- Contratos de Outros e de segmento bloqueados até revisão jurídica (D9).
