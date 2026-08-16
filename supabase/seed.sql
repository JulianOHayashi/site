-- ============================================================================
-- BDFlow canonical local seed
-- Baseline configuration only.
--
-- Included:
--   6 commercial niches
--   1 initial commercial region (Grande Vitória / ES)
--   5 cities belonging to that region
--
-- Intentionally excluded:
--   commercial exclusivities
--   commercial opportunities
--   site administrators
--   legal documents
--   users / profiles
--   orders / payments / production data
-- ============================================================================

BEGIN;

INSERT INTO public.commercial_niches
    (code, display_name, contracted_quantity, sort_order, is_active)
VALUES
    ('supermarket',       'Supermercado',          24, 1, true),
    ('pharmacy',          'Farmácia',              12, 2, true),
    ('womens_clothing',   'Roupas femininas',      12, 3, true),
    ('mens_clothing',     'Roupas masculinas',     12, 4, true),
    ('womens_footwear',   'Calçados femininos',    12, 5, true),
    ('mens_footwear',     'Calçados masculinos',   12, 6, true);

INSERT INTO public.commercial_regions
    (id, uf, name, slug, is_active)
VALUES
    (
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Grande Vitória',
        'grande-vitoria',
        true
    );

INSERT INTO public.commercial_region_cities
    (id, region_id, uf, city_name, city_key, is_active)
VALUES
    (
        '43726e7f-4241-4970-9587-4c675899737d',
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Cariacica',
        'cariacica',
        true
    ),
    (
        '0f7748ac-a1cb-4df9-9b6c-bd6a684f1196',
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Serra',
        'serra',
        true
    ),
    (
        '14054aca-bc1f-4e46-8c08-7cf0a6eff9d5',
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Viana',
        'viana',
        true
    ),
    (
        '9e6c06f9-df8d-4d44-af59-b03827067dde',
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Vila Velha',
        'vila-velha',
        true
    ),
    (
        'c70f3f98-6e8d-4749-a592-91a5a73ea8ef',
        '2bc3af58-6d5e-4456-a5a1-2f92314ef2fd',
        'ES',
        'Vitória',
        'vitoria',
        true
    );

COMMIT;