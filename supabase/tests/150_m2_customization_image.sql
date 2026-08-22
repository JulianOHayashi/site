-- ============================================================================
-- SUITE 150 — Imagem de personalização obrigatória (R7). Continua sobre 140.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_titular from auth.users where email = 'titular_m2@teste.local' \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select o.id as ord1, o.company_id as company1 from public.commercial_exclusivity_orders o limit 1 \gset
select auth_user_id as uid_mgr from public.site_company_members
 where company_id = :'company1' and role='partner_manager' limit 1 \gset

-- ---------------------------------------------------------------------------
-- Bucket privado e policies (padrão canônico)
-- ---------------------------------------------------------------------------
select tests.check('bucket de personalizacao e PRIVADO com limite e MIME',
    (select public = false and file_size_limit = 10485760
        and allowed_mime_types @> array['image/jpeg','image/png','image/webp']
       from storage.buckets where id = 'partner-customization-images'));
select tests.check('anon nao tem policy no bucket de personalizacao',
    (select count(*) from pg_policies
      where schemaname='storage' and tablename='objects'
        and policyname like 'm2_custom_img%' and 'anon' = any(roles)) = 0);
select tests.check('NAO existe policy de DELETE para o titular (sem corrida)',
    (select count(*) from pg_policies
      where schemaname='storage' and tablename='objects'
        and policyname like 'm2_custom_img%' and cmd = 'DELETE') = 0);

-- ---------------------------------------------------------------------------
-- Caminho derivado no servidor
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.request_customization_image_path((:'ord1')::uuid) as p_neg \gset
select tests.check('terceiro nao obtem caminho de upload',
    ((:'p_neg')::jsonb ->> 'reason') = 'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_mgr');
select public.request_customization_image_path((:'ord1')::uuid) as p_mgr \gset
select tests.check('manager nao obtem caminho (dominio financeiro do owner)',
    ((:'p_mgr')::jsonb ->> 'reason') = 'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.request_customization_image_path((:'ord1')::uuid) as p1 \gset
select tests.check('owner obtem caminho derivado do servidor',
    ((:'p1')::jsonb ->> 'ok') = 'true'
    and ((:'p1')::jsonb ->> 'bucket') = 'partner-customization-images'
    and ((:'p1')::jsonb ->> 'storage_path') like (:'ord1' || '/%'));
select public.request_customization_image_path((:'ord1')::uuid) as p2 \gset
select tests.check('cada pedido de caminho gera destino NOVO (sem sobrescrita)',
    ((:'p1')::jsonb ->> 'storage_path') <> ((:'p2')::jsonb ->> 'storage_path'));
commit;

select ((:'p1')::jsonb ->> 'storage_path') as path1 \gset

-- ---------------------------------------------------------------------------
-- Registro exige objeto REAL no Storage
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image((:'ord1')::uuid, :'path1') as r_sem \gset
select tests.check('registro sem objeto no Storage e recusado',
    ((:'r_sem')::jsonb ->> 'reason') = 'storage_object_not_found');
select public.register_customization_image((:'ord1')::uuid, 'outro-pedido/x.png') as r_path \gset
select tests.check('caminho fora do pedido e recusado',
    ((:'r_path')::jsonb ->> 'reason') = 'invalid_path');
commit;

-- Sobe o objeto (o que o navegador faria via Storage) e registra.
insert into storage.objects (bucket_id, name, owner, metadata)
values ('partner-customization-images', :'path1', :'uid_titular',
        jsonb_build_object('size', 204800, 'mimetype', 'image/png'));

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image(
    (:'ord1')::uuid, :'path1', 'image/webp', 999999999) as reg1 \gset
select tests.check('registro aceito com objeto real',
    ((:'reg1')::jsonb ->> 'ok') = 'true');
-- MIME/tamanho AUTORITATIVOS do Storage vencem o que o cliente declarou.
select tests.check('MIME e tamanho vem do Storage, nao do cliente',
    ((:'reg1')::jsonb ->> 'mime_type') = 'image/png'
    and ((:'reg1')::jsonb ->> 'byte_size')::bigint = 204800);
commit;

select tests.check('pedido passa a ter imagem corrente',
    public.order_has_customization_image((:'ord1')::uuid) = true);

-- Objeto de OUTRO dono não pode ser registrado.
select tests.mk_user('dono_alheio') as uid_alheio \gset
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.request_customization_image_path((:'ord1')::uuid) as p3 \gset
commit;
select ((:'p3')::jsonb ->> 'storage_path') as path3 \gset
insert into storage.objects (bucket_id, name, owner, metadata)
values ('partner-customization-images', :'path3', :'uid_alheio',
        jsonb_build_object('size', 1024, 'mimetype', 'image/png'));
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image((:'ord1')::uuid, :'path3') as r_alheio \gset
select tests.check('objeto de outro dono nao e registrado',
    ((:'r_alheio')::jsonb ->> 'reason') = 'storage_object_not_owned');
rollback;

-- MIME e tamanho inválidos vindos do Storage
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.request_customization_image_path((:'ord1')::uuid) as p4 \gset
commit;
select ((:'p4')::jsonb ->> 'storage_path') as path4 \gset
insert into storage.objects (bucket_id, name, owner, metadata)
values ('partner-customization-images', :'path4', :'uid_titular',
        jsonb_build_object('size', 1024, 'mimetype', 'application/pdf'));
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image((:'ord1')::uuid, :'path4') as r_mime \gset
select tests.check('MIME nao permitido e recusado',
    ((:'r_mime')::jsonb ->> 'reason') = 'invalid_mime');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.request_customization_image_path((:'ord1')::uuid) as p5 \gset
commit;
select ((:'p5')::jsonb ->> 'storage_path') as path5 \gset
insert into storage.objects (bucket_id, name, owner, metadata)
values ('partner-customization-images', :'path5', :'uid_titular',
        jsonb_build_object('size', 20971520, 'mimetype', 'image/png'));
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image((:'ord1')::uuid, :'path5') as r_size \gset
select tests.check('tamanho acima do limite e recusado',
    ((:'r_size')::jsonb ->> 'reason') = 'invalid_size');
rollback;

-- ---------------------------------------------------------------------------
-- Substituição append-only
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.request_customization_image_path((:'ord1')::uuid) as p6 \gset
commit;
select ((:'p6')::jsonb ->> 'storage_path') as path6 \gset
insert into storage.objects (bucket_id, name, owner, metadata)
values ('partner-customization-images', :'path6', :'uid_titular',
        jsonb_build_object('size', 51200, 'mimetype', 'image/webp'));
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.register_customization_image((:'ord1')::uuid, :'path6') as reg2 \gset
select tests.check('nova versao registrada', ((:'reg2')::jsonb ->> 'ok') = 'true');
commit;

select tests.check('apenas UMA imagem corrente por pedido',
    (select count(*) from public.commercial_order_customization_images
      where order_id = :'ord1' and is_current) = 1);
select tests.check('versao anterior vira historico (nao some)',
    (select count(*) from public.commercial_order_customization_images
      where order_id = :'ord1') = 2
    and (select count(*) from public.commercial_order_customization_images
          where order_id = :'ord1' and status = 'replaced' and replaced_at is not null) = 1);

select id as img_hist from public.commercial_order_customization_images
 where order_id = :'ord1' and status = 'replaced' limit 1 \gset
select tests.check_raises('metadado de imagem e imutavel',
  format($sql$update public.commercial_order_customization_images
           set byte_size = 1 where id = %L$sql$, :'img_hist'),
  'imagem_imutavel');
select tests.check_raises('metadado de imagem nao pode ser excluido',
  format($sql$delete from public.commercial_order_customization_images where id = %L$sql$, :'img_hist'),
  'imagem_imutavel');
select tests.check_raises('versao substituida nao volta a ser corrente',
  format($sql$update public.commercial_order_customization_images
           set is_current = true where id = %L$sql$, :'img_hist'),
  'imagem_imutavel');

-- ---------------------------------------------------------------------------
-- RLS de leitura
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('owner ve as imagens do proprio pedido',
    (select count(*) from public.commercial_order_customization_images) = 2);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check('terceiro nao ve imagem alheia',
    (select count(*) from public.commercial_order_customization_images) = 0);
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao le metadados de imagem',
  'select count(*) from public.commercial_order_customization_images',
  'permission denied');
rollback;

select tests.finish('150_m2_customization_image');
