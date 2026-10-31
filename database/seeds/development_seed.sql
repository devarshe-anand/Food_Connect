-- DEVELOPMENT ONLY. Apply manually after initialization; never included in the Docker image.
BEGIN;

INSERT INTO users (id, full_name, email, password_hash, account_status, email_verified)
VALUES
  ('10000000-0000-4000-8000-000000000001', 'Food Connect Dev Donor', 'donor@example.test',
   crypt('dev-only-password-change-me', gen_salt('bf')), 'ACTIVE', TRUE),
  ('10000000-0000-4000-8000-000000000002', 'Food Connect Dev NGO', 'ngo@example.test',
   crypt('dev-only-password-change-me', gen_salt('bf')), 'ACTIVE', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO organizations (
  id, name, type, registration_number, registration_country, address_line_1,
  locality, country_code, location, verification_status, verified_at
)
VALUES
  ('20000000-0000-4000-8000-000000000001', 'Dev Kitchen', 'RESTAURANT', 'DEV-DONOR-001', 'IN',
   '1 Demo Street', 'Bengaluru', 'IN',
   ST_SetSRID(ST_MakePoint(77.5946, 12.9716), 4326)::geography, 'VERIFIED', now()),
  ('20000000-0000-4000-8000-000000000002', 'Dev Community NGO', 'NGO', 'DEV-NGO-001', 'IN',
   '2 Demo Street', 'Bengaluru', 'IN',
   ST_SetSRID(ST_MakePoint(77.6000, 12.9750), 4326)::geography, 'VERIFIED', now())
ON CONFLICT DO NOTHING;

INSERT INTO organization_members (organization_id, user_id, role, status)
VALUES
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'OWNER', 'ACTIVE'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'OWNER', 'ACTIVE')
ON CONFLICT DO NOTHING;

COMMIT;
