# ⚠️ ANEXO TÉCNICO PRELIMINAR — NÃO APROVADO — SEM VALOR DE HOMOLOGAÇÃO

**Bandeira publicitária sobre veículo — especificação preliminar**

- Data: 2026-11-10.
- Modalidade no sistema: `vehicle_roof_visual_flag`.
- Status: **PRELIMINAR**. Este documento **não** foi elaborado nem aprovado
  por engenheiro ou responsável técnico. **Não** foi submetido a órgão de
  trânsito ou a autoridade municipal. **Não** comprova a segurança nem a
  legalidade do conjunto instalado.
- Para virar a "especificação técnica aprovada" citada nos contratos, uma
  versão revisada precisa ser:
  - assinada por responsável técnico habilitado, com registro profissional e
    laudo;
  - registrada em `commercial_advertising_specs` como `draft` e aprovada pela
    transição `draft → approved`, por ato administrativo deliberado.

## 1. O que está definido hoje

| Elemento | Valor | Natureza |
|---|---|---|
| Dimensão visual de referência da **arte** | **490 mm (largura) × 305 mm (altura)** (49 × 30,5 cm) | Referência nominal informada pela SmallFlags |
| Posição | Sobre o veículo (parte superior), por meio de suporte apropriado | Intenção de produto, sem projeto |
| Natureza | Exclusivamente visual (sem som, luz ou tela) | Definição de objeto |

## 2. Elementos que precisam ser definidos separadamente

Nenhum dos itens abaixo está especificado. **Não inventar valores.**

| # | Elemento | O que definir | Situação |
|---|---|---|---|
| E1 | Dimensão da arte | Área útil impressa e margens (a referência 490 × 305 mm é da arte) | Referência definida; tolerâncias pendentes |
| E2 | Dimensão física final do material | Largura, altura e espessura do material acabado, incluindo bainhas e reforços | PENDENTE |
| E3 | Suporte e sistema de fixação | Tipo (mastro, base, rack, ventosa, magnético, garra), pontos de fixação, travas, compatibilidade com teto e bagageiro | PENDENTE |
| E4 | Altura total do conjunto instalado | Altura acima do teto e altura total do veículo com o conjunto | PENDENTE |
| E5 | Massa e material | Massa do conjunto, tecido ou substrato, tintas, resistência UV e água | PENDENTE |
| E6 | Resistência ao vento e à vibração | Velocidade máxima de uso, ensaio ou cálculo, fator de segurança, comportamento em rajada | PENDENTE |
| E7 | Compatibilidade com veículos | Classes permitidas e excluídas (automóvel, utilitário, moto, veículo de aplicativo, táxi), teto solar, antenas, bagageiro original | PENDENTE |
| E8 | Inspeção e manutenção | Checklist pré-uso, periodicidade, desgaste, troca de componentes, registro | PENDENTE |
| E9 | Instalação e remoção | Quem executa, procedimento, torque e travas, verificação final, remoção em vias específicas | PENDENTE |
| E10 | Critérios de interrupção por risco | Avaria, folga, vento acima de limite, chuva forte, via de alta velocidade, fiscalização | PENDENTE |
| E11 | Interferências com o veículo | Visibilidade do condutor, sinalização, luzes, placas, dispositivos obrigatórios, para-brisa e vidros | PENDENTE |
| E12 | Enquadramento regulatório | Se o conjunto é acessório ou modificação de característica (CTB, art. 98; Res. Contran 916/2022) e se exige autorização ou CSV | PENDENTE (ver Matriz Regulatória) |

## 3. Lista objetiva para o responsável técnico confirmar

1. Material, dimensões finais e massa da bandeira acabada (E2, E5).
2. Projeto do suporte e da fixação, com memória de cálculo ou ensaio de
   resistência a vento e vibração na velocidade máxima admitida (E3, E6).
3. Altura total instalada por classe de veículo e limites aceitáveis (E4, E7).
4. Lista de veículos ou classes compatíveis e de impedimentos: teto solar,
   teto de vidro, antena, ausência de pontos de fixação (E7).
5. Confirmação de que o conjunto não interfere na visibilidade, nas luzes, na
   sinalização e nas placas (E11).
6. Procedimento de instalação, de verificação pós-instalação e de remoção (E9).
7. Checklist e periodicidade de inspeção e manutenção (E8).
8. Critérios objetivos de interrupção por risco (E10).
9. Parecer sobre o enquadramento: acessório ou modificação de característica, e
   necessidade de autorização prévia ou de inspeção de segurança veicular (E12).
10. Registro profissional do responsável, laudo e hash do laudo, para registro
    da versão aprovada.

## 4. Registro no sistema (somente depois da aprovação)

A versão aprovada é registrada em `commercial_advertising_specs` com:
- `spec_code` e `spec_version`;
- `modality = 'vehicle_roof_visual_flag'`;
- `artwork_reference_width_mm = 490` e `artwork_reference_height_mm = 305`, ou
  os valores aprovados;
- `source_hash`: SHA-256 deste anexo na versão aprovada;
- `technical_responsible_name`, `technical_responsible_registration` e
  `technical_report_hash`;
- `approved_by` e `approved_at`.

Depois de aprovada, a versão é imutável: só pode ser arquivada, e o
arquivamento não altera nenhum outro campo. **Nenhuma
versão foi registrada nesta branch.**
