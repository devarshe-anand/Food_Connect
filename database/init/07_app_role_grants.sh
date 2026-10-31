#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP_DB_USER:?APP_DB_USER must be configured}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 \
  --set=app_user="$APP_DB_USER" <<'SQL'
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'app_user') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'app_user') \gexec
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA public TO %I', :'app_user') \gexec
SELECT format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', :'app_user') \gexec
SELECT format('REVOKE ALL ON FUNCTION write_audit_log(uuid, character varying, character varying, uuid, jsonb, jsonb) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION match_eligible_ngos(geography) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION notify_eligible_ngos(uuid, uuid) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION accept_donation(uuid, uuid, uuid) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION confirm_handover(uuid, uuid, uuid, handover_confirmation_type, text) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION claim_notification_outbox(uuid, integer, integer) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION complete_notification_outbox(uuid, uuid) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION fail_notification_outbox(uuid, uuid, text) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION review_organization(uuid, uuid, organization_verification_status, text) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION review_organization_document(uuid, uuid, document_verification_status, text) FROM PUBLIC') \gexec
SELECT format('REVOKE ALL ON FUNCTION manage_organization_member(uuid, uuid, uuid, membership_role, membership_status) FROM PUBLIC') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION match_eligible_ngos(geography) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION notify_eligible_ngos(uuid, uuid) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION accept_donation(uuid, uuid, uuid) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION confirm_handover(uuid, uuid, uuid, handover_confirmation_type, text) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION claim_notification_outbox(uuid, integer, integer) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION complete_notification_outbox(uuid, uuid) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION fail_notification_outbox(uuid, uuid, text) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION review_organization(uuid, uuid, organization_verification_status, text) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION review_organization_document(uuid, uuid, document_verification_status, text) TO %I', :'app_user') \gexec
SELECT format('GRANT EXECUTE ON FUNCTION manage_organization_member(uuid, uuid, uuid, membership_role, membership_status) TO %I', :'app_user') \gexec
SELECT format('REVOKE INSERT, UPDATE, DELETE ON users, organizations, organization_members, organization_documents, donations, donation_claims, notifications, handover_confirmations, audit_logs, notification_outbox, refresh_tokens FROM %I', :'app_user') \gexec
SELECT format('GRANT INSERT (full_name, email, phone_number, password_hash) ON users TO %I', :'app_user') \gexec
SELECT format('GRANT INSERT (name, type, registration_number, registration_country, tax_identifier, address_line_1, address_line_2, locality, administrative_area, postal_code, country_code, contact_email, contact_phone, location, logo_storage_path) ON organizations TO %I', :'app_user') \gexec
SELECT format('GRANT INSERT (organization_id, document_type, storage_path) ON organization_documents TO %I', :'app_user') \gexec
SELECT format('GRANT INSERT (donor_organization_id, title, description, category, quantity, unit, prepared_at, expires_at, pickup_deadline, pickup_address, pickup_location, image_storage_path) ON donations TO %I', :'app_user') \gexec
SELECT format('GRANT INSERT (user_id, token_hash, expires_at, replaced_by_token_id) ON refresh_tokens TO %I', :'app_user') \gexec
SELECT format('GRANT UPDATE (full_name, phone_number, password_hash, account_status, email_verified, phone_verified, last_login_at, updated_at, deleted_at) ON users TO %I', :'app_user') \gexec
SELECT format('GRANT UPDATE (name, registration_number, registration_country, tax_identifier, address_line_1, address_line_2, locality, administrative_area, postal_code, country_code, contact_email, contact_phone, location, logo_storage_path, updated_at, deleted_at) ON organizations TO %I', :'app_user') \gexec
SELECT format('GRANT UPDATE (title, description, category, quantity, unit, prepared_at, expires_at, pickup_deadline, pickup_address, pickup_location, image_storage_path, updated_at, cancelled_at) ON donations TO %I', :'app_user') \gexec
SELECT format('GRANT UPDATE (read_at) ON notifications TO %I', :'app_user') \gexec
SELECT format('GRANT UPDATE (revoked_at, replaced_by_token_id) ON refresh_tokens TO %I', :'app_user') \gexec
SQL
