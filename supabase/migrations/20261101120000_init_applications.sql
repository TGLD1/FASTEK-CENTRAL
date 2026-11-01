-- ============================================================
-- Migration : Initialisation de base + table applications
-- Date     : 2026-11-01
-- Phase    : 2 - Base de données et sécurité
-- ============================================================

-- 1. Extensions nécessaires
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Table applications
CREATE TABLE public.applications (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    public_id           text NOT NULL UNIQUE,
    name                text NOT NULL,
    description         text,
    status              text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'maintenance', 'retired')),
    current_version     text,
    min_version         text,
    sdk_version         text,
    capabilities        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- 3. Index utiles
CREATE INDEX idx_applications_public_id ON public.applications (public_id);
CREATE INDEX idx_applications_status ON public.applications (status);

-- 4. Trigger pour updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS \[ BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END; \] LANGUAGE plpgsql;

CREATE TRIGGER trg_applications_updated_at
    BEFORE UPDATE ON public.applications
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- 5. Commentaires
COMMENT ON TABLE public.applications IS 'Registre des applications FASTEK (Notea, Cleaner, etc.)';
COMMENT ON COLUMN public.applications.public_id IS 'Identifiant public permanent utilisé par les clients et le SDK';
COMMENT ON COLUMN public.applications.capabilities IS 'Capacités déclarées et autorisées (jsonb)';

-- 6. RLS (activée dès le départ)
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;

-- Pour l''instant : seule la service_role peut tout faire.
-- Les politiques plus fines (admin) seront ajoutées plus tard.
CREATE POLICY "Service role full access on applications"
    ON public.applications
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
