CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(200) NOT NULL,
  email VARCHAR(320) NOT NULL,
  phone_number VARCHAR(32),
  password_hash VARCHAR(255) NOT NULL,
  platform_role platform_role NOT NULL DEFAULT 'USER',
  account_status user_account_status NOT NULL DEFAULT 'PENDING',
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  phone_verified BOOLEAN NOT NULL DEFAULT FALSE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) NOT NULL,
  type organization_type NOT NULL,
  registration_number VARCHAR(100),
  registration_country CHAR(2),
  tax_identifier VARCHAR(100),
  address_line_1 VARCHAR(200) NOT NULL,
  address_line_2 VARCHAR(200),
  locality VARCHAR(120) NOT NULL,
  administrative_area VARCHAR(120),
  postal_code VARCHAR(24),
  country_code CHAR(2) NOT NULL,
  contact_email VARCHAR(320),
  contact_phone VARCHAR(32),
  location GEOGRAPHY(Point, 4326),
  verification_status organization_verification_status NOT NULL DEFAULT 'PENDING',
  operational_status organization_operational_status NOT NULL DEFAULT 'ACTIVE',
  logo_storage_path TEXT,
  verified_at TIMESTAMPTZ,
  verified_by_user_id UUID,
  verification_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role membership_role NOT NULL DEFAULT 'MEMBER',
  status membership_status NOT NULL DEFAULT 'INVITED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE organization_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  document_type organization_document_type NOT NULL,
  storage_path TEXT NOT NULL,
  verification_status document_verification_status NOT NULL DEFAULT 'PENDING',
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by_user_id UUID,
  reviewer_notes TEXT
);

CREATE TABLE donations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  donor_organization_id UUID NOT NULL,
  accepted_by_organization_id UUID,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  category donation_category NOT NULL,
  quantity NUMERIC(12, 3) NOT NULL,
  unit donation_unit NOT NULL,
  prepared_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  pickup_deadline TIMESTAMPTZ NOT NULL,
  pickup_address TEXT NOT NULL,
  pickup_location GEOGRAPHY(Point, 4326) NOT NULL,
  status donation_status NOT NULL DEFAULT 'AVAILABLE',
  image_storage_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

CREATE TABLE donation_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  donation_id UUID NOT NULL,
  ngo_organization_id UUID NOT NULL,
  status donation_claim_status NOT NULL DEFAULT 'NOTIFIED',
  notified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id UUID,
  recipient_organization_id UUID,
  donation_id UUID,
  notification_type notification_type NOT NULL,
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key VARCHAR(255) NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT notification_has_recipient CHECK (
    recipient_user_id IS NOT NULL OR recipient_organization_id IS NOT NULL
  )
);

CREATE TABLE handover_confirmations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  donation_id UUID NOT NULL,
  organization_id UUID NOT NULL,
  confirmed_by_user_id UUID NOT NULL,
  confirmation_type handover_confirmation_type NOT NULL,
  evidence_storage_path TEXT,
  confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_type VARCHAR(10) NOT NULL,
  actor_user_id UUID,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100) NOT NULL,
  entity_id UUID NOT NULL,
  old_values JSONB,
  new_values JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT audit_actor_type CHECK (
    (actor_type = 'USER' AND actor_user_id IS NOT NULL)
    OR (actor_type = 'SYSTEM' AND actor_user_id IS NULL)
  )
);

CREATE TABLE notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(100) NOT NULL,
  aggregate_type VARCHAR(100) NOT NULL,
  aggregate_id UUID NOT NULL,
  idempotency_key VARCHAR(255) NOT NULL,
  payload JSONB NOT NULL,
  status outbox_status NOT NULL DEFAULT 'PENDING',
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 8,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_by UUID,
  lease_expires_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  replaced_by_token_id UUID
);

CREATE TABLE schema_migrations (
  version VARCHAR(100) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  checksum VARCHAR(128) NOT NULL
);
