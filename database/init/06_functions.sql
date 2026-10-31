CREATE OR REPLACE FUNCTION match_eligible_ngos(p_pickup_location GEOGRAPHY)
RETURNS TABLE (ngo_organization_id UUID, distance_meters DOUBLE PRECISION)
LANGUAGE sql
STABLE
STRICT
AS $$
  SELECT o.id, ST_Distance(o.location, p_pickup_location)
  FROM organizations AS o
  WHERE o.type = 'NGO'
    AND o.verification_status = 'VERIFIED'
    AND o.operational_status = 'ACTIVE'
    AND o.deleted_at IS NULL
    AND o.location IS NOT NULL
    AND ST_DWithin(o.location, p_pickup_location, 5000)
  ORDER BY ST_Distance(o.location, p_pickup_location), o.id
$$;

CREATE OR REPLACE FUNCTION write_audit_log(
  p_actor_user_id UUID,
  p_action VARCHAR,
  p_entity_type VARCHAR,
  p_entity_id UUID,
  p_old_values JSONB,
  p_new_values JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO audit_logs (actor_type, actor_user_id, action, entity_type, entity_id, old_values, new_values)
  VALUES (
    CASE WHEN p_actor_user_id IS NULL THEN 'SYSTEM' ELSE 'USER' END,
    p_actor_user_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_old_values,
    p_new_values
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION notify_eligible_ngos(p_donation_id UUID, p_actor_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation donations%ROWTYPE;
  v_match RECORD;
  v_count INTEGER := 0;
  v_claim_id UUID;
BEGIN
  SELECT * INTO v_donation FROM donations WHERE id = p_donation_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found', p_donation_id USING ERRCODE = 'P0002';
  END IF;
  IF v_donation.status <> 'AVAILABLE' OR v_donation.pickup_deadline <= now() THEN
    RAISE EXCEPTION 'Donation % is not available for notification', p_donation_id USING ERRCODE = 'P0001';
  END IF;
  IF p_actor_user_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM organization_members AS m
    JOIN users AS u ON u.id = m.user_id
    WHERE m.organization_id = v_donation.donor_organization_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'ACTIVE'
      AND u.account_status = 'ACTIVE'
      AND u.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'An active donor organization member must publish the donation'
      USING ERRCODE = '42501';
  END IF;

  FOR v_match IN
    SELECT m.ngo_organization_id, m.distance_meters
    FROM match_eligible_ngos(v_donation.pickup_location) AS m
  LOOP
    INSERT INTO donation_claims (donation_id, ngo_organization_id, status)
    VALUES (p_donation_id, v_match.ngo_organization_id, 'NOTIFIED')
    ON CONFLICT (donation_id, ngo_organization_id) DO NOTHING
    RETURNING id INTO v_claim_id;

    IF v_claim_id IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO notifications (
      recipient_user_id, recipient_organization_id, donation_id, notification_type,
      title, message, payload, idempotency_key
    )
    SELECT
      m.user_id, v_match.ngo_organization_id, p_donation_id, 'DONATION_AVAILABLE',
      'Food donation available',
      format('%s is available for pickup.', v_donation.title),
      jsonb_build_object(
        'donationId', p_donation_id,
        'ngoOrganizationId', v_match.ngo_organization_id,
        'distanceMeters', round(v_match.distance_meters::numeric, 2)
      ),
      format('donation-available:%s:%s:%s', p_donation_id, v_match.ngo_organization_id, m.user_id)
    FROM organization_members AS m
    JOIN users AS u ON u.id = m.user_id
    WHERE m.organization_id = v_match.ngo_organization_id
      AND m.status = 'ACTIVE'
      AND u.account_status = 'ACTIVE'
      AND u.deleted_at IS NULL
    ON CONFLICT (idempotency_key) DO NOTHING;

    INSERT INTO notification_outbox (
      event_type, aggregate_type, aggregate_id, idempotency_key, payload
    )
    VALUES (
      'DONATION_AVAILABLE',
      'donation',
      p_donation_id,
      format('donation-available:%s:%s', p_donation_id, v_match.ngo_organization_id),
      jsonb_build_object(
        'donationId', p_donation_id,
        'ngoOrganizationId', v_match.ngo_organization_id,
        'distanceMeters', round(v_match.distance_meters::numeric, 2)
      )
    )
    ON CONFLICT (idempotency_key) DO NOTHING;

    v_count := v_count + 1;
    v_claim_id := NULL;
  END LOOP;

  PERFORM write_audit_log(
    p_actor_user_id,
    'DONATION_NGOS_NOTIFIED',
    'donation',
    p_donation_id,
    NULL,
    jsonb_build_object('matchedNgoCount', v_count)
  );
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION review_organization(
  p_organization_id UUID,
  p_actor_user_id UUID,
  p_status organization_verification_status,
  p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old organizations%ROWTYPE;
  v_audit_id UUID;
BEGIN
  IF p_status = 'PENDING' THEN
    RAISE EXCEPTION 'Organization review must approve or reject' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = p_actor_user_id AND platform_role = 'ADMIN'
      AND account_status = 'ACTIVE' AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'An active platform administrator is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM organizations WHERE id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  UPDATE organizations
  SET verification_status = p_status,
      verified_at = CASE WHEN p_status = 'VERIFIED' THEN now() ELSE NULL END,
      verified_by_user_id = CASE WHEN p_status = 'VERIFIED' THEN p_actor_user_id ELSE NULL END,
      verification_notes = p_notes,
      updated_at = now()
  WHERE id = p_organization_id;

  v_audit_id := write_audit_log(
    p_actor_user_id, 'ORGANIZATION_REVIEWED', 'organization', p_organization_id,
    jsonb_build_object('verificationStatus', v_old.verification_status),
    jsonb_build_object('verificationStatus', p_status, 'notes', p_notes)
  );
  INSERT INTO notification_outbox (event_type, aggregate_type, aggregate_id, idempotency_key, payload)
  VALUES (
    'ORGANIZATION_STATUS', 'organization', p_organization_id,
    format('organization-reviewed:%s', v_audit_id),
    jsonb_build_object('organizationId', p_organization_id, 'verificationStatus', p_status)
  );
  INSERT INTO notifications (
    recipient_user_id, recipient_organization_id, notification_type,
    title, message, payload, idempotency_key
  )
  SELECT
    m.user_id, p_organization_id, 'ORGANIZATION_STATUS',
    'Organization verification updated',
    format('Your organization verification status is now %s.', p_status),
    jsonb_build_object('organizationId', p_organization_id, 'verificationStatus', p_status),
    format('organization-reviewed:%s:%s', v_audit_id, m.user_id)
  FROM organization_members AS m
  JOIN users AS u ON u.id = m.user_id
  WHERE m.organization_id = p_organization_id
    AND m.status = 'ACTIVE' AND u.account_status = 'ACTIVE' AND u.deleted_at IS NULL
  ON CONFLICT (idempotency_key) DO NOTHING;
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION review_organization_document(
  p_document_id UUID,
  p_actor_user_id UUID,
  p_status document_verification_status,
  p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old organization_documents%ROWTYPE;
BEGIN
  IF p_status = 'PENDING' THEN
    RAISE EXCEPTION 'Document review must approve or reject' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = p_actor_user_id AND platform_role = 'ADMIN'
      AND account_status = 'ACTIVE' AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'An active platform administrator is required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM organization_documents WHERE id = p_document_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  UPDATE organization_documents
  SET verification_status = p_status,
      reviewed_at = now(),
      reviewed_by_user_id = p_actor_user_id,
      reviewer_notes = p_notes
  WHERE id = p_document_id;
  PERFORM write_audit_log(
    p_actor_user_id, 'ORGANIZATION_DOCUMENT_REVIEWED', 'organization_document', p_document_id,
    jsonb_build_object('verificationStatus', v_old.verification_status),
    jsonb_build_object('verificationStatus', p_status, 'notes', p_notes)
  );
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION manage_organization_member(
  p_organization_id UUID,
  p_actor_user_id UUID,
  p_member_user_id UUID,
  p_role membership_role,
  p_status membership_status
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_role membership_role;
  v_existing organization_members%ROWTYPE;
  v_member_id UUID;
BEGIN
  PERFORM 1 FROM organizations WHERE id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % was not found', p_organization_id USING ERRCODE = 'P0002';
  END IF;

  SELECT role INTO v_actor_role
  FROM organization_members AS m
  JOIN users AS u ON u.id = m.user_id
  WHERE m.organization_id = p_organization_id
    AND m.user_id = p_actor_user_id
    AND m.status = 'ACTIVE'
    AND u.account_status = 'ACTIVE'
    AND u.deleted_at IS NULL;

  SELECT * INTO v_existing
  FROM organization_members
  WHERE organization_id = p_organization_id AND user_id = p_member_user_id
  FOR UPDATE;

  IF v_actor_role IS NULL THEN
    IF NOT (
      p_actor_user_id = p_member_user_id
      AND p_role = 'OWNER'
      AND p_status = 'ACTIVE'
      AND NOT EXISTS (
        SELECT 1 FROM organization_members WHERE organization_id = p_organization_id
      )
    ) AND NOT (
      p_actor_user_id = p_member_user_id
      AND v_existing.status = 'INVITED'
      AND p_status = 'ACTIVE'
      AND p_role = v_existing.role
    ) THEN
      RAISE EXCEPTION 'An active organization owner/admin or valid invitee is required'
        USING ERRCODE = '42501';
    END IF;
  ELSIF v_actor_role NOT IN ('OWNER', 'ADMIN') THEN
    RAISE EXCEPTION 'Only organization owners/admins can manage memberships'
      USING ERRCODE = '42501';
  END IF;

  IF p_role = 'OWNER' AND v_actor_role IS NOT NULL AND v_actor_role <> 'OWNER' THEN
    RAISE EXCEPTION 'Only an organization owner can assign another owner'
      USING ERRCODE = '42501';
  END IF;
  IF p_status = 'ACTIVE' AND NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = p_member_user_id AND account_status = 'ACTIVE' AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'An active user account is required for active membership'
      USING ERRCODE = '22023';
  END IF;

  IF v_existing.id IS NOT NULL
     AND v_existing.status = 'ACTIVE'
     AND v_existing.role = 'OWNER'
     AND (p_status <> 'ACTIVE' OR p_role <> 'OWNER')
     AND NOT EXISTS (
       SELECT 1 FROM organization_members
       WHERE organization_id = p_organization_id
         AND user_id <> p_member_user_id AND role = 'OWNER' AND status = 'ACTIVE'
     ) THEN
    RAISE EXCEPTION 'An organization must retain at least one active owner'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO organization_members (organization_id, user_id, role, status)
  VALUES (p_organization_id, p_member_user_id, p_role, p_status)
  ON CONFLICT (organization_id, user_id)
  DO UPDATE SET role = EXCLUDED.role, status = EXCLUDED.status, updated_at = now()
  RETURNING id INTO v_member_id;

  PERFORM write_audit_log(
    p_actor_user_id,
    'ORGANIZATION_MEMBERSHIP_CHANGED',
    'organization_member',
    v_member_id,
    CASE WHEN v_existing.id IS NULL THEN NULL
      ELSE jsonb_build_object('role', v_existing.role, 'status', v_existing.status) END,
    jsonb_build_object('organizationId', p_organization_id, 'userId', p_member_user_id,
      'role', p_role, 'status', p_status)
  );
  RETURN v_member_id;
END;
$$;

CREATE OR REPLACE FUNCTION accept_donation(
  p_donation_id UUID,
  p_ngo_organization_id UUID,
  p_actor_user_id UUID
)
RETURNS TABLE (success BOOLEAN, result_code TEXT, accepted_ngo_organization_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation donations%ROWTYPE;
  v_claim donation_claims%ROWTYPE;
  v_org organizations%ROWTYPE;
  v_member RECORD;
BEGIN
  SELECT * INTO v_donation FROM donations WHERE id = p_donation_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'NOT_FOUND'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF v_donation.status <> 'AVAILABLE' OR v_donation.pickup_deadline <= now() THEN
    RETURN QUERY SELECT FALSE, 'ALREADY_CLAIMED_OR_UNAVAILABLE'::TEXT,
      v_donation.accepted_by_organization_id;
    RETURN;
  END IF;

  SELECT * INTO v_claim
  FROM donation_claims
  WHERE donation_id = p_donation_id AND ngo_organization_id = p_ngo_organization_id
  FOR UPDATE;
  IF NOT FOUND OR v_claim.status <> 'NOTIFIED' THEN
    RETURN QUERY SELECT FALSE, 'NGO_NOT_NOTIFIED'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  SELECT * INTO v_org
  FROM organizations
  WHERE id = p_ngo_organization_id
    AND type = 'NGO'
    AND verification_status = 'VERIFIED'
    AND operational_status = 'ACTIVE'
    AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'NGO_NOT_ELIGIBLE'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM organization_members AS m
    JOIN users AS u ON u.id = m.user_id
    WHERE m.organization_id = p_ngo_organization_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'ACTIVE'
      AND u.account_status = 'ACTIVE'
      AND u.deleted_at IS NULL
  ) THEN
    RETURN QUERY SELECT FALSE, 'ACTOR_NOT_ACTIVE_NGO_MEMBER'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  UPDATE donations
  SET status = 'CLAIMED', accepted_by_organization_id = p_ngo_organization_id, updated_at = now()
  WHERE id = p_donation_id;
  UPDATE donation_claims
  SET status = 'ACCEPTED', accepted_at = now(), updated_at = now()
  WHERE id = v_claim.id;
  UPDATE donation_claims
  SET status = 'LOST', updated_at = now()
  WHERE donation_id = p_donation_id AND id <> v_claim.id AND status = 'NOTIFIED';

  FOR v_member IN
    SELECT m.user_id, m.organization_id
    FROM organization_members AS m
    JOIN users AS u ON u.id = m.user_id
    WHERE m.organization_id = v_donation.donor_organization_id
      AND m.status = 'ACTIVE' AND u.account_status = 'ACTIVE' AND u.deleted_at IS NULL
  LOOP
    INSERT INTO notifications (
      recipient_user_id, recipient_organization_id, donation_id, notification_type,
      title, message, payload, idempotency_key
    )
    VALUES (
      v_member.user_id, v_member.organization_id, p_donation_id, 'DONATION_CLAIMED',
      'Donation accepted',
      format('%s has accepted your donation.', v_org.name),
      jsonb_build_object(
        'donationId', p_donation_id,
        'ngoOrganizationId', v_org.id,
        'ngoName', v_org.name,
        'ngoContactEmail', v_org.contact_email,
        'ngoContactPhone', v_org.contact_phone
      ),
      format('donation-claimed:%s:donor:%s', p_donation_id, v_member.user_id)
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  FOR v_member IN
    SELECT DISTINCT m.organization_id, m.user_id
    FROM donation_claims AS c
    JOIN organization_members AS m ON m.organization_id = c.ngo_organization_id AND m.status = 'ACTIVE'
    JOIN users AS u ON u.id = m.user_id AND u.account_status = 'ACTIVE' AND u.deleted_at IS NULL
    WHERE c.donation_id = p_donation_id AND c.status = 'LOST'
  LOOP
    INSERT INTO notifications (
      recipient_user_id, recipient_organization_id, donation_id, notification_type,
      title, message, payload, idempotency_key
    )
    VALUES (
      v_member.user_id, v_member.organization_id, p_donation_id, 'DONATION_UNAVAILABLE',
      'Donation already accepted',
      'Another NGO accepted this donation first.',
      jsonb_build_object('donationId', p_donation_id, 'acceptedByOrganizationId', v_org.id),
      format('donation-unavailable:%s:%s:%s', p_donation_id, v_member.organization_id, v_member.user_id)
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  INSERT INTO notification_outbox (event_type, aggregate_type, aggregate_id, idempotency_key, payload)
  VALUES
    (
      'DONATION_CLAIMED', 'donation', p_donation_id,
      format('donation-claimed:%s', p_donation_id),
      jsonb_build_object(
        'donationId', p_donation_id,
        'ngoOrganizationId', v_org.id,
        'ngoName', v_org.name,
        'ngoContactEmail', v_org.contact_email,
        'ngoContactPhone', v_org.contact_phone
      )
    ),
    (
      'DONATION_CLAIM_LOST', 'donation', p_donation_id,
      format('donation-claim-lost:%s', p_donation_id),
      jsonb_build_object('donationId', p_donation_id, 'acceptedNgoOrganizationId', v_org.id)
    )
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM write_audit_log(
    p_actor_user_id,
    'DONATION_ACCEPTED',
    'donation',
    p_donation_id,
    jsonb_build_object('status', 'AVAILABLE', 'acceptedByOrganizationId', NULL),
    jsonb_build_object('status', 'CLAIMED', 'acceptedByOrganizationId', v_org.id)
  );

  RETURN QUERY SELECT TRUE, 'ACCEPTED'::TEXT, v_org.id;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_handover(
  p_donation_id UUID,
  p_organization_id UUID,
  p_actor_user_id UUID,
  p_confirmation_type handover_confirmation_type,
  p_evidence_storage_path TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation donations%ROWTYPE;
  v_expected_org_id UUID;
  v_inserted_id UUID;
  v_confirmed_count INTEGER;
  v_recipient RECORD;
  v_other_org_id UUID;
BEGIN
  SELECT * INTO v_donation FROM donations WHERE id = p_donation_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'NOT_FOUND';
  END IF;
  IF v_donation.status NOT IN ('CLAIMED', 'COLLECTED') THEN
    RETURN 'DONATION_NOT_IN_HANDOVER';
  END IF;

  v_expected_org_id := CASE p_confirmation_type
    WHEN 'DONOR' THEN v_donation.donor_organization_id
    WHEN 'NGO' THEN v_donation.accepted_by_organization_id
  END;
  IF v_expected_org_id IS DISTINCT FROM p_organization_id THEN
    RETURN 'ORGANIZATION_NOT_A_HANDOVER_PARTY';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM organization_members AS m
    JOIN users AS u ON u.id = m.user_id
    WHERE m.organization_id = p_organization_id
      AND m.user_id = p_actor_user_id
      AND m.status = 'ACTIVE'
      AND u.account_status = 'ACTIVE'
      AND u.deleted_at IS NULL
  ) THEN
    RETURN 'ACTOR_NOT_ACTIVE_ORGANIZATION_MEMBER';
  END IF;

  INSERT INTO handover_confirmations (
    donation_id, organization_id, confirmed_by_user_id, confirmation_type, evidence_storage_path
  )
  VALUES (p_donation_id, p_organization_id, p_actor_user_id, p_confirmation_type, p_evidence_storage_path)
  ON CONFLICT (donation_id, confirmation_type) DO NOTHING
  RETURNING id INTO v_inserted_id;
  IF v_inserted_id IS NULL THEN
    RETURN 'ALREADY_CONFIRMED';
  END IF;

  v_other_org_id := CASE p_confirmation_type
    WHEN 'DONOR' THEN v_donation.accepted_by_organization_id
    WHEN 'NGO' THEN v_donation.donor_organization_id
  END;

  INSERT INTO notifications (
    recipient_user_id, recipient_organization_id, donation_id, notification_type,
    title, message, payload, idempotency_key
  )
  SELECT
    m.user_id, m.organization_id, p_donation_id, 'HANDOVER_CONFIRMED',
    'Handover confirmation received',
    'The other organization confirmed the food handover.',
    jsonb_build_object('donationId', p_donation_id, 'confirmationType', p_confirmation_type),
    format('handover-confirmed:%s:%s:%s', p_donation_id, p_confirmation_type, m.user_id)
  FROM organization_members AS m
  JOIN users AS u ON u.id = m.user_id
  WHERE m.organization_id = v_other_org_id
    AND m.status = 'ACTIVE' AND u.account_status = 'ACTIVE' AND u.deleted_at IS NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  SELECT count(*) INTO v_confirmed_count
  FROM handover_confirmations WHERE donation_id = p_donation_id;

  PERFORM write_audit_log(
    p_actor_user_id,
    'HANDOVER_CONFIRMED',
    'donation',
    p_donation_id,
    jsonb_build_object('status', v_donation.status),
    jsonb_build_object('confirmationType', p_confirmation_type, 'organizationId', p_organization_id)
  );

  INSERT INTO notification_outbox (event_type, aggregate_type, aggregate_id, idempotency_key, payload)
  VALUES (
    'HANDOVER_CONFIRMED',
    'donation',
    p_donation_id,
    format('handover-confirmed:%s:%s', p_donation_id, p_confirmation_type),
    jsonb_build_object('donationId', p_donation_id, 'confirmationType', p_confirmation_type)
  )
  ON CONFLICT (idempotency_key) DO NOTHING;
  INSERT INTO notifications (
    recipient_user_id, recipient_organization_id, donation_id, notification_type,
    title, message, payload, idempotency_key
  )
  SELECT
    m.user_id, m.organization_id, p_donation_id, 'DONATION_COMPLETED',
    'Donation completed',
    'Both organizations confirmed the food handover.',
    jsonb_build_object('donationId', p_donation_id),
    format('donation-completed:%s:%s', p_donation_id, m.user_id)
  FROM organization_members AS m
  JOIN users AS u ON u.id = m.user_id
  WHERE m.organization_id IN (v_donation.donor_organization_id, v_donation.accepted_by_organization_id)
    AND m.status = 'ACTIVE' AND u.account_status = 'ACTIVE' AND u.deleted_at IS NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  IF v_confirmed_count = 2 THEN
    UPDATE donations
    SET status = 'COMPLETED', completed_at = now(), updated_at = now()
    WHERE id = p_donation_id;
    PERFORM write_audit_log(
      p_actor_user_id,
      'DONATION_COMPLETED',
      'donation',
      p_donation_id,
      jsonb_build_object('status', v_donation.status),
      jsonb_build_object('status', 'COMPLETED')
    );
    INSERT INTO notification_outbox (event_type, aggregate_type, aggregate_id, idempotency_key, payload)
    VALUES (
      'DONATION_COMPLETED', 'donation', p_donation_id,
      format('donation-completed:%s', p_donation_id),
      jsonb_build_object('donationId', p_donation_id)
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
    RETURN 'COMPLETED';
  END IF;

  UPDATE donations SET status = 'COLLECTED', updated_at = now() WHERE id = p_donation_id;
  RETURN 'CONFIRMED_WAITING_FOR_OTHER_PARTY';
END;
$$;

CREATE OR REPLACE FUNCTION claim_notification_outbox(
  p_worker_id UUID,
  p_batch_size INTEGER DEFAULT 25,
  p_lease_seconds INTEGER DEFAULT 60
)
RETURNS SETOF notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_batch_size < 1 OR p_batch_size > 500 OR p_lease_seconds < 1 THEN
    RAISE EXCEPTION 'Invalid outbox batch or lease size';
  END IF;

  UPDATE notification_outbox
  SET status = 'DEAD',
      locked_by = NULL,
      lease_expires_at = NULL,
      last_error = COALESCE(last_error, 'Processing lease expired after maximum attempts'),
      updated_at = now()
  WHERE status = 'PROCESSING'
    AND lease_expires_at < now()
    AND attempts >= max_attempts;

  RETURN QUERY
  WITH candidates AS (
    SELECT o.id
    FROM notification_outbox AS o
    WHERE (o.status = 'PENDING' AND o.available_at <= now())
       OR (o.status = 'PROCESSING' AND o.lease_expires_at < now() AND o.attempts < o.max_attempts)
    ORDER BY o.available_at, o.created_at
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE notification_outbox AS o
  SET status = 'PROCESSING',
      attempts = o.attempts + 1,
      locked_by = p_worker_id,
      lease_expires_at = now() + make_interval(secs => p_lease_seconds),
      updated_at = now()
  FROM candidates AS c
  WHERE o.id = c.id
  RETURNING o.*;
END;
$$;

CREATE OR REPLACE FUNCTION complete_notification_outbox(p_event_id UUID, p_worker_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE notification_outbox
  SET status = 'DELIVERED', processed_at = now(), locked_by = NULL,
      lease_expires_at = NULL, last_error = NULL, updated_at = now()
  WHERE id = p_event_id AND status = 'PROCESSING' AND locked_by = p_worker_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count = 1;
END;
$$;

CREATE OR REPLACE FUNCTION fail_notification_outbox(p_event_id UUID, p_worker_id UUID, p_error TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row notification_outbox%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM notification_outbox
  WHERE id = p_event_id AND status = 'PROCESSING' AND locked_by = p_worker_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'LEASE_NOT_OWNED';
  END IF;

  UPDATE notification_outbox
  SET status = CASE WHEN attempts >= max_attempts THEN 'DEAD'::outbox_status ELSE 'PENDING'::outbox_status END,
      available_at = CASE
        WHEN attempts >= max_attempts THEN available_at
        ELSE now() + make_interval(secs => LEAST(3600, (2 ^ LEAST(attempts, 12))::INTEGER))
      END,
      locked_by = NULL,
      lease_expires_at = NULL,
      last_error = left(p_error, 4000),
      updated_at = now()
  WHERE id = p_event_id;

  RETURN CASE WHEN v_row.attempts >= v_row.max_attempts THEN 'DEAD' ELSE 'RETRY_SCHEDULED' END;
END;
$$;
