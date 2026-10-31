ALTER TABLE users
  ADD CONSTRAINT users_name_nonempty CHECK (length(btrim(full_name)) > 0),
  ADD CONSTRAINT users_email_nonempty CHECK (length(btrim(email)) > 0),
  ADD CONSTRAINT users_email_trimmed CHECK (email = btrim(email)),
  ADD CONSTRAINT users_phone_e164 CHECK (
    phone_number IS NULL OR phone_number ~ '^\+[1-9][0-9]{1,14}$'
  ),
  ADD CONSTRAINT users_password_hash_nonempty CHECK (length(password_hash) >= 20);

ALTER TABLE organizations
  ADD CONSTRAINT organizations_name_nonempty CHECK (length(btrim(name)) > 0),
  ADD CONSTRAINT organizations_country_code_format CHECK (country_code ~ '^[A-Z]{2}$'),
  ADD CONSTRAINT organizations_registration_country_format CHECK (
    registration_country IS NULL OR registration_country ~ '^[A-Z]{2}$'
  ),
  ADD CONSTRAINT organizations_verified_metadata CHECK (
    (verification_status = 'VERIFIED' AND verified_at IS NOT NULL)
    OR (verification_status <> 'VERIFIED' AND verified_at IS NULL)
  ),
  ADD CONSTRAINT organizations_not_own_reviewer CHECK (
    verified_by_user_id IS NULL OR verification_status = 'VERIFIED'
  );

ALTER TABLE organization_members
  ADD CONSTRAINT organization_members_unique_pair UNIQUE (organization_id, user_id);

ALTER TABLE organization_documents
  ADD CONSTRAINT organization_documents_path_nonempty CHECK (length(btrim(storage_path)) > 0),
  ADD CONSTRAINT organization_documents_review_metadata CHECK (
    (verification_status = 'PENDING' AND reviewed_at IS NULL AND reviewed_by_user_id IS NULL)
    OR (verification_status <> 'PENDING' AND reviewed_at IS NOT NULL AND reviewed_by_user_id IS NOT NULL)
  );

ALTER TABLE donations
  ADD CONSTRAINT donations_title_nonempty CHECK (length(btrim(title)) > 0),
  ADD CONSTRAINT donations_positive_quantity CHECK (quantity > 0),
  ADD CONSTRAINT donations_date_order CHECK (
    pickup_deadline <= expires_at AND (prepared_at IS NULL OR prepared_at <= expires_at)
  ),
  ADD CONSTRAINT donations_claim_status_consistency CHECK (
    (status IN ('AVAILABLE', 'CANCELLED', 'EXPIRED') AND accepted_by_organization_id IS NULL)
    OR (status IN ('CLAIMED', 'COLLECTED', 'COMPLETED') AND accepted_by_organization_id IS NOT NULL)
  ),
  ADD CONSTRAINT donations_completion_timestamp CHECK (
    (status = 'COMPLETED' AND completed_at IS NOT NULL)
    OR (status <> 'COMPLETED' AND completed_at IS NULL)
  ),
  ADD CONSTRAINT donations_cancel_timestamp CHECK (
    (status = 'CANCELLED' AND cancelled_at IS NOT NULL)
    OR (status <> 'CANCELLED' AND cancelled_at IS NULL)
  );

ALTER TABLE donation_claims
  ADD CONSTRAINT donation_claims_unique_ngo UNIQUE (donation_id, ngo_organization_id),
  ADD CONSTRAINT donation_claims_acceptance_metadata CHECK (
    (status = 'ACCEPTED' AND accepted_at IS NOT NULL)
    OR (status <> 'ACCEPTED' AND accepted_at IS NULL)
  );

ALTER TABLE notifications
  ADD CONSTRAINT notifications_idempotency_unique UNIQUE (idempotency_key),
  ADD CONSTRAINT notifications_payload_object CHECK (jsonb_typeof(payload) = 'object');

ALTER TABLE handover_confirmations
  ADD CONSTRAINT handover_confirmation_once_per_side UNIQUE (donation_id, confirmation_type),
  ADD CONSTRAINT handover_evidence_path_nonempty CHECK (
    evidence_storage_path IS NULL OR length(btrim(evidence_storage_path)) > 0
  );

ALTER TABLE notification_outbox
  ADD CONSTRAINT notification_outbox_idempotency_unique UNIQUE (idempotency_key),
  ADD CONSTRAINT notification_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object'),
  ADD CONSTRAINT notification_outbox_attempt_bounds CHECK (
    attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts
  ),
  ADD CONSTRAINT notification_outbox_lease_consistency CHECK (
    (status = 'PROCESSING' AND locked_by IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR (status <> 'PROCESSING' AND locked_by IS NULL AND lease_expires_at IS NULL)
  ),
  ADD CONSTRAINT notification_outbox_processed_consistency CHECK (
    (status = 'DELIVERED' AND processed_at IS NOT NULL)
    OR (status <> 'DELIVERED' AND processed_at IS NULL)
  );

ALTER TABLE refresh_tokens
  ADD CONSTRAINT refresh_tokens_hash_unique UNIQUE (token_hash),
  ADD CONSTRAINT refresh_tokens_not_expired_on_insert CHECK (expires_at > created_at),
  ADD CONSTRAINT refresh_tokens_not_self_replacement CHECK (
    replaced_by_token_id IS NULL OR replaced_by_token_id <> id
  );

ALTER TABLE organization_members
  ADD CONSTRAINT organization_members_organization_fk
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  ADD CONSTRAINT organization_members_user_fk
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE organizations
  ADD CONSTRAINT organizations_verified_by_fk
    FOREIGN KEY (verified_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE organization_documents
  ADD CONSTRAINT organization_documents_organization_fk
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  ADD CONSTRAINT organization_documents_reviewer_fk
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE donations
  ADD CONSTRAINT donations_donor_organization_fk
    FOREIGN KEY (donor_organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
  ADD CONSTRAINT donations_accepted_organization_fk
    FOREIGN KEY (accepted_by_organization_id) REFERENCES organizations(id) ON DELETE RESTRICT;

ALTER TABLE donation_claims
  ADD CONSTRAINT donation_claims_donation_fk
    FOREIGN KEY (donation_id) REFERENCES donations(id) ON DELETE CASCADE,
  ADD CONSTRAINT donation_claims_ngo_fk
    FOREIGN KEY (ngo_organization_id) REFERENCES organizations(id) ON DELETE RESTRICT;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_recipient_user_fk
    FOREIGN KEY (recipient_user_id) REFERENCES users(id) ON DELETE CASCADE,
  ADD CONSTRAINT notifications_recipient_organization_fk
    FOREIGN KEY (recipient_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  ADD CONSTRAINT notifications_donation_fk
    FOREIGN KEY (donation_id) REFERENCES donations(id) ON DELETE CASCADE;

ALTER TABLE handover_confirmations
  ADD CONSTRAINT handover_donation_fk
    FOREIGN KEY (donation_id) REFERENCES donations(id) ON DELETE CASCADE,
  ADD CONSTRAINT handover_organization_fk
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
  ADD CONSTRAINT handover_user_fk
    FOREIGN KEY (confirmed_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE audit_logs
  ADD CONSTRAINT audit_actor_user_fk
    FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE refresh_tokens
  ADD CONSTRAINT refresh_tokens_user_fk
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  ADD CONSTRAINT refresh_tokens_replacement_fk
    FOREIGN KEY (replaced_by_token_id) REFERENCES refresh_tokens(id) ON DELETE SET NULL;
