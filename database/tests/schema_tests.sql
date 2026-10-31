\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_donor_id UUID := '30000000-0000-4000-8000-000000000001';
  v_ngo_near_id UUID := '30000000-0000-4000-8000-000000000002';
  v_ngo_far_id UUID := '30000000-0000-4000-8000-000000000003';
  v_pending_org_id UUID := '30000000-0000-4000-8000-000000000004';
  v_document_id UUID := '30000000-0000-4000-8000-000000000005';
  v_donor_user UUID := '40000000-0000-4000-8000-000000000001';
  v_ngo_user UUID := '40000000-0000-4000-8000-000000000002';
  v_far_user UUID := '40000000-0000-4000-8000-000000000003';
  v_admin_user UUID := '40000000-0000-4000-8000-000000000004';
  v_donation UUID := '50000000-0000-4000-8000-000000000001';
  v_location GEOGRAPHY := ST_SetSRID(ST_MakePoint(77.5946, 12.9716), 4326)::geography;
  v_match_count INTEGER;
  v_result RECORD;
  v_handover_result TEXT;
  v_constraint_rejected BOOLEAN;
  v_worker_id UUID := '60000000-0000-4000-8000-000000000001';
  v_outbox_row notification_outbox%ROWTYPE;
  v_claimed_outbox_count INTEGER := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
    RAISE EXCEPTION 'PostGIS extension is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'pgcrypto extension is missing';
  END IF;

  INSERT INTO users (id, full_name, email, password_hash, account_status, email_verified)
  VALUES
    (v_donor_user, 'Test donor', 'schema-donor@example.test', repeat('x', 30), 'ACTIVE', TRUE),
    (v_ngo_user, 'Test NGO user', 'schema-ngo@example.test', repeat('x', 30), 'ACTIVE', TRUE),
    (v_far_user, 'Test far NGO user', 'schema-far@example.test', repeat('x', 30), 'ACTIVE', TRUE),
    (v_admin_user, 'Test admin', 'schema-admin@example.test', repeat('x', 30), 'ACTIVE', TRUE);
  UPDATE users SET platform_role = 'ADMIN' WHERE id = v_admin_user;

  v_constraint_rejected := FALSE;
  BEGIN
    INSERT INTO users (full_name, email, password_hash)
    VALUES ('Duplicate email', 'SCHEMA-DONOR@example.test', repeat('x', 30));
  EXCEPTION WHEN unique_violation THEN
    v_constraint_rejected := TRUE;
  END;
  IF NOT v_constraint_rejected THEN
    RAISE EXCEPTION 'Case-insensitive live email uniqueness was not enforced';
  END IF;

  INSERT INTO organizations (
    id, name, type, registration_number, registration_country, address_line_1,
    locality, country_code, location, verification_status, verified_at
  )
  VALUES
    (v_donor_id, 'Test Donor', 'RESTAURANT', 'TEST-D-001', 'IN', '1 Test Rd',
     'Test City', 'IN', v_location, 'VERIFIED', now()),
    (v_ngo_near_id, 'Near NGO', 'NGO', 'TEST-N-001', 'IN', '2 Test Rd',
     'Test City', 'IN', ST_Project(v_location, 1000, radians(90)), 'VERIFIED', now()),
    (v_ngo_far_id, 'Far NGO', 'NGO', 'TEST-N-002', 'IN', '3 Test Rd',
     'Test City', 'IN', ST_Project(v_location, 6000, radians(90)), 'VERIFIED', now());

  INSERT INTO organizations (
    id, name, type, registration_number, registration_country, address_line_1,
    locality, country_code, location
  )
  VALUES (
    v_pending_org_id, 'Pending NGO', 'NGO', 'TEST-N-003', 'IN', '4 Test Rd',
    'Test City', 'IN', ST_Project(v_location, 10000, radians(90))
  );
  INSERT INTO organization_documents (id, organization_id, document_type, storage_path)
  VALUES (v_document_id, v_pending_org_id, 'NGO_REGISTRATION', 'verification/test-document.pdf');
  IF NOT review_organization(v_pending_org_id, v_admin_user, 'VERIFIED', 'Test review')
     OR NOT review_organization_document(v_document_id, v_admin_user, 'APPROVED', NULL) THEN
    RAISE EXCEPTION 'Admin organization/document review failed';
  END IF;

  INSERT INTO organization_members (organization_id, user_id, role, status)
  VALUES
    (v_donor_id, v_donor_user, 'OWNER', 'ACTIVE'),
    (v_ngo_near_id, v_ngo_user, 'OWNER', 'ACTIVE'),
    (v_ngo_far_id, v_far_user, 'OWNER', 'ACTIVE');

  v_constraint_rejected := FALSE;
  BEGIN
    INSERT INTO organization_members (organization_id, user_id)
    VALUES (v_donor_id, '90000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN foreign_key_violation THEN
    v_constraint_rejected := TRUE;
  END;
  IF NOT v_constraint_rejected THEN
    RAISE EXCEPTION 'Membership user foreign key was not enforced';
  END IF;

  IF (SELECT count(*) FROM match_eligible_ngos(v_location)) <> 1
     OR (SELECT ngo_organization_id FROM match_eligible_ngos(v_location)) <> v_ngo_near_id THEN
    RAISE EXCEPTION '5 km matching failed to include near NGO and exclude far NGO';
  END IF;

  INSERT INTO donations (
    id, donor_organization_id, title, category, quantity, unit,
    expires_at, pickup_deadline, pickup_address, pickup_location
  )
  VALUES (
    v_donation, v_donor_id, 'Test meal', 'MEALS', 20, 'PORTION',
    now() + interval '4 hours', now() + interval '2 hours', '1 Test Rd', v_location
  );

  v_constraint_rejected := FALSE;
  BEGIN
    INSERT INTO donations (
      donor_organization_id, title, category, quantity, unit, expires_at,
      pickup_deadline, pickup_address, pickup_location
    )
    VALUES (
      v_donor_id, 'Invalid quantity', 'MEALS', 0, 'PORTION', now() + interval '4 hours',
      now() + interval '2 hours', '1 Test Rd', v_location
    );
  EXCEPTION WHEN check_violation THEN
    v_constraint_rejected := TRUE;
  END;
  IF NOT v_constraint_rejected THEN
    RAISE EXCEPTION 'Positive donation quantity constraint was not enforced';
  END IF;

  v_match_count := notify_eligible_ngos(v_donation, v_donor_user);
  IF v_match_count <> 1 THEN
    RAISE EXCEPTION 'Expected one eligible NGO notification, got %', v_match_count;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE donation_id = v_donation AND recipient_organization_id = v_ngo_near_id
      AND notification_type = 'DONATION_AVAILABLE'
  ) THEN
    RAISE EXCEPTION 'Expected database notification for eligible NGO';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM notification_outbox WHERE aggregate_id = v_donation) THEN
    RAISE EXCEPTION 'Expected outbox event for the notification';
  END IF;
  IF notify_eligible_ngos(v_donation, v_donor_user) <> 0 THEN
    RAISE EXCEPTION 'Repeated notification setup should not create duplicate claims';
  END IF;

  SELECT * INTO v_result FROM accept_donation(v_donation, v_ngo_near_id, v_ngo_user);
  IF NOT v_result.success OR v_result.result_code <> 'ACCEPTED' THEN
    RAISE EXCEPTION 'Expected acceptance; got %', v_result.result_code;
  END IF;

  v_constraint_rejected := FALSE;
  BEGIN
    INSERT INTO donation_claims (donation_id, ngo_organization_id, status, accepted_at)
    VALUES (v_donation, v_ngo_far_id, 'ACCEPTED', now());
  EXCEPTION WHEN unique_violation THEN
    v_constraint_rejected := TRUE;
  END;
  IF NOT v_constraint_rejected THEN
    RAISE EXCEPTION 'Only one accepted claim per donation must be enforced';
  END IF;

  SELECT * INTO v_result FROM accept_donation(v_donation, v_ngo_far_id, v_far_user);
  IF v_result.success OR v_result.result_code <> 'ALREADY_CLAIMED_OR_UNAVAILABLE' THEN
    RAISE EXCEPTION 'Second NGO acceptance did not fail safely';
  END IF;

  v_handover_result := confirm_handover(v_donation, v_donor_id, v_donor_user, 'DONOR');
  IF v_handover_result <> 'CONFIRMED_WAITING_FOR_OTHER_PARTY'
     OR (SELECT status FROM donations WHERE id = v_donation) <> 'COLLECTED' THEN
    RAISE EXCEPTION 'Donation should await the second handover confirmation';
  END IF;
  IF confirm_handover(v_donation, v_donor_id, v_donor_user, 'DONOR') <> 'ALREADY_CONFIRMED' THEN
    RAISE EXCEPTION 'Duplicate donor confirmation should be rejected';
  END IF;
  v_handover_result := confirm_handover(v_donation, v_ngo_near_id, v_ngo_user, 'NGO');
  IF v_handover_result <> 'COMPLETED'
     OR (SELECT status FROM donations WHERE id = v_donation) <> 'COMPLETED' THEN
    RAISE EXCEPTION 'Donation should complete after both confirmations';
  END IF;

  IF (SELECT count(*) FROM audit_logs WHERE entity_id = v_donation) < 3 THEN
    RAISE EXCEPTION 'Expected auditable donation events';
  END IF;
  IF (SELECT count(*) FROM donation_claims WHERE donation_id = v_donation AND status = 'ACCEPTED') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one accepted NGO claim';
  END IF;
  IF (SELECT count(*) FROM handover_confirmations WHERE donation_id = v_donation) <> 2 THEN
    RAISE EXCEPTION 'Expected exactly two handover confirmations';
  END IF;

  FOR v_outbox_row IN
    SELECT * FROM claim_notification_outbox(v_worker_id, 500, 60)
  LOOP
    v_claimed_outbox_count := v_claimed_outbox_count + 1;
    IF NOT complete_notification_outbox(v_outbox_row.id, v_worker_id) THEN
      RAISE EXCEPTION 'Outbox event lease completion failed';
    END IF;
  END LOOP;
  IF v_claimed_outbox_count = 0 THEN
    RAISE EXCEPTION 'Expected outbox worker to claim pending events';
  END IF;
END;
$$;

ROLLBACK;
