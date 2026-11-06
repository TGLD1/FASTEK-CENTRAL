BEGIN;

-- =========================================================
-- 1. SESSIONS D'AUTHENTIFICATION DES INSTALLATIONS
-- =========================================================

CREATE TABLE public.installation_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL,
    installation_id UUID NOT NULL,

    status TEXT NOT NULL DEFAULT 'active',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,

    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT,

    CONSTRAINT uq_installation_sessions_id_application
        UNIQUE (id, application_id),

    CONSTRAINT fk_sessions_installation
        FOREIGN KEY (installation_id, application_id)
        REFERENCES public.installations (id, application_id)
        ON DELETE RESTRICT,

    CONSTRAINT installation_sessions_status_check
        CHECK (status IN ('active', 'revoked', 'expired')),

    CONSTRAINT installation_sessions_expiry_check
        CHECK (expires_at > created_at),

    CONSTRAINT installation_sessions_revocation_check
        CHECK (
            (status = 'revoked' AND revoked_at IS NOT NULL)
            OR
            (status IN ('active', 'expired') AND revoked_at IS NULL)
        )
);

-- Une seule session active par installation.
CREATE UNIQUE INDEX uq_installation_sessions_active_installation
    ON public.installation_sessions (installation_id)
    WHERE status = 'active';

CREATE INDEX idx_installation_sessions_application
    ON public.installation_sessions (application_id);

CREATE INDEX idx_installation_sessions_expiry
    ON public.installation_sessions (expires_at)
    WHERE status = 'active';


-- =========================================================
-- 2. JETONS D'ACCÈS ET DE RENOUVELLEMENT
-- =========================================================

CREATE TABLE public.installation_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    application_id UUID NOT NULL,
    session_id UUID NOT NULL,

    -- HMAC-SHA-256 : uniquement le hash, jamais le jeton brut.
    token_hash BYTEA NOT NULL,
    hash_key_id TEXT NOT NULL,

    token_type TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,

    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    replaced_by_token_id UUID,

    -- Données temporaires chiffrées pour rejouer un renouvellement.
    refresh_idempotency_key_hash BYTEA,
    refresh_response_ciphertext BYTEA,
    refresh_response_nonce BYTEA,
    refresh_response_key_id TEXT,
    refresh_response_expires_at TIMESTAMPTZ,

    CONSTRAINT uq_installation_tokens_id_session_application
        UNIQUE (id, session_id, application_id),

    CONSTRAINT uq_installation_tokens_hash
        UNIQUE (token_hash),

    CONSTRAINT fk_tokens_session
        FOREIGN KEY (session_id, application_id)
        REFERENCES public.installation_sessions (id, application_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tokens_replacement
        FOREIGN KEY (replaced_by_token_id, session_id, application_id)
        REFERENCES public.installation_tokens (id, session_id, application_id)
        ON DELETE RESTRICT,

    CONSTRAINT installation_tokens_type_check
        CHECK (token_type IN ('access', 'refresh')),

    CONSTRAINT installation_tokens_hash_check
        CHECK (octet_length(token_hash) = 32),

    CONSTRAINT installation_tokens_key_id_check
        CHECK (length(trim(hash_key_id)) > 0),

    CONSTRAINT installation_tokens_expiry_check
        CHECK (expires_at > created_at),

    CONSTRAINT installation_tokens_usage_check
        CHECK (
            (used_at IS NULL AND replaced_by_token_id IS NULL)
            OR
            (
                token_type = 'refresh'
                AND used_at IS NOT NULL
                AND replaced_by_token_id IS NOT NULL
            )
        ),

    -- Les cinq champs de rejeu doivent être tous renseignés
    -- ou tous NULL.
    CONSTRAINT installation_tokens_replay_fields_check
        CHECK (
            (
                refresh_idempotency_key_hash IS NULL
                AND refresh_response_ciphertext IS NULL
                AND refresh_response_nonce IS NULL
                AND refresh_response_key_id IS NULL
                AND refresh_response_expires_at IS NULL
            )
            OR
            (
                refresh_idempotency_key_hash IS NOT NULL
                AND octet_length(refresh_idempotency_key_hash) = 32

                AND refresh_response_ciphertext IS NOT NULL
                AND octet_length(refresh_response_ciphertext) >= 16

                AND refresh_response_nonce IS NOT NULL
                AND octet_length(refresh_response_nonce) = 12

                AND refresh_response_key_id IS NOT NULL
                AND length(trim(refresh_response_key_id)) > 0

                AND refresh_response_expires_at IS NOT NULL
                AND used_at IS NOT NULL
                AND replaced_by_token_id IS NOT NULL
                AND token_type = 'refresh'

                AND refresh_response_expires_at > used_at
                AND refresh_response_expires_at
                    <= used_at + INTERVAL '5 minutes'
            )
        )
);

-- Recherche et gestion des jetons.
CREATE INDEX idx_installation_tokens_session_type
    ON public.installation_tokens (session_id, token_type);

CREATE INDEX idx_installation_tokens_expiry
    ON public.installation_tokens (expires_at);

-- Un seul jeton d'accès non révoqué par session.
CREATE UNIQUE INDEX uq_installation_tokens_current_access
    ON public.installation_tokens (session_id)
    WHERE token_type = 'access'
      AND revoked_at IS NULL;

-- Un seul jeton de renouvellement non consommé par session.
CREATE UNIQUE INDEX uq_installation_tokens_current_refresh
    ON public.installation_tokens (session_id)
    WHERE token_type = 'refresh'
      AND revoked_at IS NULL
      AND used_at IS NULL
      AND replaced_by_token_id IS NULL;

-- Un jeton successeur ne peut avoir qu'un seul prédécesseur.
CREATE UNIQUE INDEX uq_installation_tokens_replaced_by
    ON public.installation_tokens (replaced_by_token_id)
    WHERE replaced_by_token_id IS NOT NULL;

-- Évite la réutilisation d'un nonce AES-GCM pour une même clé.
CREATE UNIQUE INDEX uq_installation_tokens_replay_nonce
    ON public.installation_tokens (
        refresh_response_key_id,
        refresh_response_nonce
    )
    WHERE refresh_response_nonce IS NOT NULL;


-- =========================================================
-- 3. SÉCURITÉ : RLS ET PRIVILÈGES
-- =========================================================

ALTER TABLE public.installation_sessions
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.installation_tokens
    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on installation_sessions"
    ON public.installation_sessions
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Service role full access on installation_tokens"
    ON public.installation_tokens
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

REVOKE ALL PRIVILEGES ON TABLE
    public.installation_sessions,
    public.installation_tokens
FROM PUBLIC, anon, authenticated;

GRANT ALL PRIVILEGES ON TABLE
    public.installation_sessions,
    public.installation_tokens
TO service_role;

COMMIT;
