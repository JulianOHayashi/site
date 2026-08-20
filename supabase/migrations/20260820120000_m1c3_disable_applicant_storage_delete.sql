-- ===========================================================================
-- M1-C3 — FECHA A CORRIDA TOCTOU DO REGISTRO DE DOCUMENTO
-- ===========================================================================
-- DEFEITO CORRIGIDO
-- register_partner_application_document lia e validava o objeto em
-- storage.objects e só depois inseria o metadado. Entre a leitura e o
-- INSERT, o próprio solicitante podia APAGAR o objeto pela policy de DELETE,
-- porque ela só exigia que ainda não existisse metadado registrado — e nesse
-- instante, de fato, não existia.
--
-- Estados finais ruins que isso permitia:
--   A) metadado existe, objeto no Storage não existe mais;
--   B) metadado descreve o objeto validado, mas o caminho passou a apontar
--      para outro conteúdo (apagar e reenviar bytes diferentes no mesmo path).
--
-- Ambos violam a propriedade central do B5: o objeto verificado pelo backend
-- tem de ser o objeto permanentemente vinculado ao metadado.
--
-- DECISÃO DE PROJETO
-- O solicitante deixa de ter DELETE direto sobre objetos do bucket privado.
-- DELETE direto é uma superfície de mutação concorrente contra a RPC de
-- registro; sem ela, a corrida some por construção, e não por sincronização.
--
-- CONSEQUÊNCIA ACEITA NO M1
-- Uma falha de registro após o upload pode deixar um objeto órfão. O órfão
-- não tem metadado, não aparece na UI, não é revisável e não é reutilizável
-- (o path novo é sempre único). A limpeza controlada fica para um fluxo
-- server-side posterior; NÃO é construída agora.
--
-- Nada mais é ampliado: bucket segue privado, upload segue restrito à pasta
-- da própria aplicação, leitura segue pelas regras existentes, isolamento
-- entre aplicações, acesso do admin e imutabilidade de path registrado
-- permanecem como estão.
-- ===========================================================================

DROP POLICY m1_partner_docs_titular_delete ON storage.objects;

-- Nenhuma policy de DELETE é criada em seu lugar. Com RLS ativa em
-- storage.objects e sem policy para o comando, DELETE é negado para toda
-- role do Data API — inclusive para o dono do próprio objeto.
--
-- service_role e o owner do schema seguem com as capacidades que já tinham
-- por privilégio de base; nenhum GRANT novo é concedido aqui.

COMMENT ON TABLE storage.objects IS
  'M1-C3: solicitantes nao possuem DELETE direto em partner-application-docs. A remocao de orfaos, se necessaria, sera um fluxo server-side controlado.';
