-- Case-insensitive email uniqueness for live accounts; deleted accounts release the address.
CREATE UNIQUE INDEX users_live_email_uq ON users (lower(email)) WHERE deleted_at IS NULL;
-- Phone numbers are optional and unique only among non-deleted accounts; normalize to E.164 in the API.
CREATE UNIQUE INDEX users_live_phone_uq ON users (phone_number)
  WHERE phone_number IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX organizations_registration_uq
  ON organizations (type, registration_country, lower(registration_number))
  WHERE registration_number IS NOT NULL AND registration_country IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX organizations_ngo_match_gix
  ON organizations USING GIST (location)
  WHERE type = 'NGO' AND verification_status = 'VERIFIED'
    AND operational_status = 'ACTIVE' AND deleted_at IS NULL;
CREATE INDEX organizations_verification_queue_idx
  ON organizations (verification_status, created_at)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX organization_members_active_pair_uq
  ON organization_members (organization_id, user_id) WHERE status = 'ACTIVE';
CREATE INDEX organization_members_user_active_idx
  ON organization_members (user_id, organization_id) WHERE status = 'ACTIVE';
CREATE INDEX organization_documents_review_queue_idx
  ON organization_documents (verification_status, uploaded_at)
  WHERE verification_status = 'PENDING';

CREATE INDEX donations_available_deadline_idx
  ON donations (pickup_deadline, created_at) WHERE status = 'AVAILABLE';
CREATE INDEX donations_donor_created_idx ON donations (donor_organization_id, created_at DESC);
CREATE INDEX donations_accepted_ngo_status_idx
  ON donations (accepted_by_organization_id, status) WHERE accepted_by_organization_id IS NOT NULL;
CREATE INDEX donations_pickup_gix ON donations USING GIST (pickup_location);

CREATE INDEX donation_claims_ngo_status_idx
  ON donation_claims (ngo_organization_id, status, notified_at DESC);
CREATE UNIQUE INDEX donation_claims_one_accepted_per_donation_uq
  ON donation_claims (donation_id) WHERE status = 'ACCEPTED';

CREATE INDEX notifications_user_unread_idx
  ON notifications (recipient_user_id, created_at DESC)
  WHERE recipient_user_id IS NOT NULL AND read_at IS NULL;
CREATE INDEX notifications_organization_unread_idx
  ON notifications (recipient_organization_id, created_at DESC)
  WHERE recipient_organization_id IS NOT NULL AND read_at IS NULL;
CREATE INDEX notifications_donation_idx ON notifications (donation_id, created_at);

CREATE INDEX handover_confirmations_donation_idx ON handover_confirmations (donation_id);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id, occurred_at DESC);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_user_id, occurred_at DESC)
  WHERE actor_user_id IS NOT NULL;

CREATE INDEX notification_outbox_ready_idx
  ON notification_outbox (available_at, created_at)
  WHERE status = 'PENDING';
CREATE INDEX notification_outbox_expired_lease_idx
  ON notification_outbox (lease_expires_at)
  WHERE status = 'PROCESSING';
CREATE INDEX refresh_tokens_user_live_idx
  ON refresh_tokens (user_id, expires_at) WHERE revoked_at IS NULL;
