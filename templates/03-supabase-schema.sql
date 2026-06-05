-- ============================================================================
-- SUPABASE DATABASE SCHEMA
-- AI Voice Agent Agency - Home Services
-- ============================================================================
--
-- HOW TO USE:
-- 1. Go to your Supabase Dashboard > SQL Editor
-- 2. Paste this entire file
-- 3. Click "Run"
-- 4. Verify tables in Table Editor
--
-- MULTI-TENANT DESIGN:
-- Every table has a client_id column. Row Level Security (RLS) ensures
-- each client can only see their own data. Your agency (service_role key)
-- can see everything.
-- ============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- TABLE 1: clients
-- The businesses your agency serves (your customers).
-- One row per HVAC company, plumber, roofer, etc.
-- ============================================================================

CREATE TABLE clients (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Business info
    business_name       TEXT NOT NULL,
    owner_name          TEXT NOT NULL,
    email               TEXT NOT NULL,
    phone               TEXT NOT NULL,
    address             TEXT,
    city                TEXT,
    state               TEXT,
    zip                 TEXT,
    website             TEXT,
    service_types       TEXT[] DEFAULT '{}',           -- e.g., {'hvac','plumbing','electrical'}
    service_area        TEXT,                          -- "Greater Phoenix metro"

    -- Vapi / Twilio config
    vapi_assistant_id   TEXT,                          -- links to the Vapi assistant for this client
    twilio_phone_number TEXT,                          -- the Twilio number assigned to this client
    notification_email  TEXT,                          -- where to send alerts (can differ from email)
    notification_phone  TEXT,                          -- where to send SMS alerts

    -- Operational settings
    business_hours      JSONB DEFAULT '{
        "monday":    {"open": "08:00", "close": "17:00"},
        "tuesday":   {"open": "08:00", "close": "17:00"},
        "wednesday": {"open": "08:00", "close": "17:00"},
        "thursday":  {"open": "08:00", "close": "17:00"},
        "friday":    {"open": "08:00", "close": "17:00"},
        "saturday":  {"open": "09:00", "close": "13:00"},
        "sunday":    null
    }'::JSONB,
    timezone            TEXT DEFAULT 'America/New_York',
    emergency_enabled   BOOLEAN DEFAULT true,
    auto_sms_leads      BOOLEAN DEFAULT true,          -- auto-text new web leads
    spanish_support     BOOLEAN DEFAULT false,
    service_call_fee    TEXT,                           -- e.g., "$89"

    -- Billing
    plan                TEXT DEFAULT 'starter'
                        CHECK (plan IN ('starter', 'growth', 'premium')),
    monthly_rate        NUMERIC(10,2) DEFAULT 0,
    billing_email       TEXT,
    stripe_customer_id  TEXT,

    -- Status
    status              TEXT DEFAULT 'active'
                        CHECK (status IN ('active', 'paused', 'cancelled', 'onboarding')),
    onboarded_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookups by Vapi assistant ID (used in every webhook)
CREATE INDEX idx_clients_vapi_assistant_id ON clients(vapi_assistant_id);
CREATE INDEX idx_clients_status ON clients(status);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- TABLE 2: calls
-- Every call handled by the AI, whether completed, missed, or abandoned.
-- ============================================================================

CREATE TABLE calls (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id           UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,

    -- Vapi call data
    vapi_call_id        TEXT UNIQUE,                   -- Vapi's call ID
    caller_phone        TEXT,                          -- the phone number that called in
    direction           TEXT DEFAULT 'inbound'
                        CHECK (direction IN ('inbound', 'outbound')),

    -- Call details
    duration_seconds    INTEGER DEFAULT 0,
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,

    -- AI analysis (from Vapi end-of-call-report)
    transcript          TEXT,                          -- full conversation transcript
    summary             TEXT,                          -- AI-generated summary
    structured_data     JSONB,                        -- extracted fields from structured output
    recording_url       TEXT,                          -- link to call recording if enabled

    -- Outcome
    outcome             TEXT DEFAULT 'unknown'
                        CHECK (outcome IN (
                            'completed',               -- AI handled the full conversation
                            'missed',                  -- caller hung up before completion
                            'transferred',             -- transferred to a human
                            'voicemail',               -- went to voicemail
                            'spam',                    -- identified as spam/solicitor
                            'unknown'
                        )),
    appointment_booked  BOOLEAN DEFAULT false,
    message_taken       BOOLEAN DEFAULT false,

    -- Metadata
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_calls_client_id ON calls(client_id);
CREATE INDEX idx_calls_created_at ON calls(created_at DESC);
CREATE INDEX idx_calls_outcome ON calls(outcome);
CREATE INDEX idx_calls_client_date ON calls(client_id, created_at DESC);


-- ============================================================================
-- TABLE 3: leads
-- Captured caller information -- every person who calls or submits a form.
-- ============================================================================

CREATE TABLE leads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id           UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    call_id             UUID REFERENCES calls(id) ON DELETE SET NULL,

    -- Contact info
    caller_name         TEXT,
    phone_number        TEXT,
    email               TEXT,
    address             TEXT,
    city                TEXT,
    state               TEXT,
    zip                 TEXT,

    -- Service request
    service_needed      TEXT,                          -- "AC not blowing cold air"
    service_category    TEXT,                          -- "ac_repair", "plumbing", etc.
    urgency             TEXT DEFAULT 'medium'
                        CHECK (urgency IN ('low', 'medium', 'high', 'emergency')),
    is_existing_customer BOOLEAN DEFAULT false,

    -- Source tracking
    source              TEXT DEFAULT 'phone'
                        CHECK (source IN ('phone', 'website', 'sms', 'referral', 'other')),

    -- Status
    status              TEXT DEFAULT 'new'
                        CHECK (status IN (
                            'new',                     -- just captured
                            'contacted',               -- client has reached out
                            'quoted',                  -- estimate/quote given
                            'scheduled',               -- appointment booked
                            'completed',               -- job done
                            'lost',                    -- did not convert
                            'spam'
                        )),

    -- Notes
    notes               TEXT,
    spanish_callback    BOOLEAN DEFAULT false,

    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_leads_client_id ON leads(client_id);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_created_at ON leads(created_at DESC);
CREATE INDEX idx_leads_phone ON leads(phone_number);
CREATE INDEX idx_leads_client_date ON leads(client_id, created_at DESC);

CREATE TRIGGER set_leads_updated_at
    BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- TABLE 4: appointments
-- Booked service appointments.
-- ============================================================================

CREATE TABLE appointments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id           UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    lead_id             UUID REFERENCES leads(id) ON DELETE SET NULL,
    call_id             UUID REFERENCES calls(id) ON DELETE SET NULL,

    -- Customer info (denormalized for quick access)
    customer_name       TEXT NOT NULL,
    customer_phone      TEXT NOT NULL,
    service_address     TEXT NOT NULL,

    -- Appointment details
    service_type        TEXT,                          -- "ac_repair", "furnace_install"
    service_description TEXT,                          -- detailed description from the call
    scheduled_date      DATE NOT NULL,
    time_window         TEXT DEFAULT 'morning'
                        CHECK (time_window IN ('morning', 'afternoon', 'evening', 'anytime')),
    estimated_duration  INTERVAL,

    -- Status
    status              TEXT DEFAULT 'scheduled'
                        CHECK (status IN (
                            'scheduled',
                            'confirmed',               -- customer confirmed
                            'dispatched',              -- technician assigned/en route
                            'completed',               -- job done
                            'cancelled',
                            'no_show',
                            'rescheduled'
                        )),
    is_emergency        BOOLEAN DEFAULT false,

    -- Technician
    technician_name     TEXT,
    technician_phone    TEXT,

    -- Notes
    notes               TEXT,

    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_appointments_client_id ON appointments(client_id);
CREATE INDEX idx_appointments_date ON appointments(scheduled_date);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointments_client_date ON appointments(client_id, scheduled_date);

CREATE TRIGGER set_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- TABLE 5: invoices
-- Your agency's billing to your clients.
-- ============================================================================

CREATE TABLE invoices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id           UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,

    -- Invoice details
    invoice_number      TEXT UNIQUE NOT NULL,          -- "INV-2026-0001"
    period_start        DATE NOT NULL,                 -- billing period start
    period_end          DATE NOT NULL,                 -- billing period end

    -- Line items stored as JSONB array
    -- Example: [{"description": "Monthly AI Receptionist - Growth Plan", "amount": 497},
    --           {"description": "Overage: 45 calls above 200 included", "amount": 67.50}]
    line_items          JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- Totals
    subtotal            NUMERIC(10,2) NOT NULL DEFAULT 0,
    tax_rate            NUMERIC(5,4) DEFAULT 0,        -- e.g., 0.0825 for 8.25%
    tax_amount          NUMERIC(10,2) DEFAULT 0,
    total               NUMERIC(10,2) NOT NULL DEFAULT 0,

    -- Payment
    status              TEXT DEFAULT 'draft'
                        CHECK (status IN ('draft', 'sent', 'paid', 'overdue', 'void')),
    due_date            DATE,
    paid_at             TIMESTAMPTZ,
    stripe_invoice_id   TEXT,
    payment_method      TEXT,                          -- "card", "ach", "check"

    -- Notes
    notes               TEXT,

    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_invoices_client_id ON invoices(client_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);

CREATE TRIGGER set_invoices_updated_at
    BEFORE UPDATE ON invoices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Generate sequential invoice numbers
CREATE SEQUENCE invoice_number_seq START 1;

CREATE OR REPLACE FUNCTION generate_invoice_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.invoice_number IS NULL THEN
        NEW.invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYY') || '-' ||
                              LPAD(NEXTVAL('invoice_number_seq')::TEXT, 4, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_invoice_number
    BEFORE INSERT ON invoices
    FOR EACH ROW EXECUTE FUNCTION generate_invoice_number();


-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================
--
-- Two access patterns:
-- 1. Your n8n workflows use the service_role key -> bypasses RLS (full access)
-- 2. Client dashboard (if you build one) uses anon key + JWT -> RLS enforced
--
-- The policies below support pattern #2. Pattern #1 works out of the box.
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

-- Clients can only see their own record
CREATE POLICY "Clients can view own record"
    ON clients FOR SELECT
    USING (id = auth.uid());

-- Clients can see their own calls
CREATE POLICY "Clients can view own calls"
    ON calls FOR SELECT
    USING (client_id = auth.uid());

-- Clients can see their own leads
CREATE POLICY "Clients can view own leads"
    ON leads FOR SELECT
    USING (client_id = auth.uid());

-- Clients can see their own appointments
CREATE POLICY "Clients can view own appointments"
    ON appointments FOR SELECT
    USING (client_id = auth.uid());

-- Clients can update their own appointment status
CREATE POLICY "Clients can update own appointments"
    ON appointments FOR UPDATE
    USING (client_id = auth.uid())
    WITH CHECK (client_id = auth.uid());

-- Clients can see their own invoices
CREATE POLICY "Clients can view own invoices"
    ON invoices FOR SELECT
    USING (client_id = auth.uid());

-- ============================================================================
-- AGENCY ADMIN POLICIES
-- If you create an agency_admins table or use a custom claim, add policies
-- like this to give your team full access through the client dashboard:
-- ============================================================================

-- Example (uncomment and adapt when you build an admin panel):
--
-- CREATE POLICY "Agency admins can view all clients"
--     ON clients FOR ALL
--     USING (
--         EXISTS (
--             SELECT 1 FROM auth.users
--             WHERE auth.users.id = auth.uid()
--             AND auth.users.raw_app_meta_data->>'role' = 'agency_admin'
--         )
--     );


-- ============================================================================
-- USEFUL VIEWS (for reporting)
-- ============================================================================

-- Daily call summary per client
CREATE OR REPLACE VIEW daily_call_summary AS
SELECT
    c.client_id,
    cl.business_name,
    DATE(c.created_at AT TIME ZONE cl.timezone) AS call_date,
    COUNT(*) AS total_calls,
    COUNT(*) FILTER (WHERE c.outcome = 'completed') AS completed,
    COUNT(*) FILTER (WHERE c.outcome = 'missed') AS missed,
    COUNT(*) FILTER (WHERE c.appointment_booked = true) AS appointments_booked,
    COUNT(*) FILTER (WHERE c.message_taken = true) AS messages_taken,
    AVG(c.duration_seconds) FILTER (WHERE c.duration_seconds > 0) AS avg_duration,
    COUNT(*) FILTER (WHERE c.outcome = 'spam') AS spam
FROM calls c
JOIN clients cl ON cl.id = c.client_id
GROUP BY c.client_id, cl.business_name, DATE(c.created_at AT TIME ZONE cl.timezone);

-- Lead conversion funnel per client
CREATE OR REPLACE VIEW lead_funnel AS
SELECT
    l.client_id,
    cl.business_name,
    COUNT(*) AS total_leads,
    COUNT(*) FILTER (WHERE l.status = 'new') AS new_leads,
    COUNT(*) FILTER (WHERE l.status = 'contacted') AS contacted,
    COUNT(*) FILTER (WHERE l.status = 'quoted') AS quoted,
    COUNT(*) FILTER (WHERE l.status = 'scheduled') AS scheduled,
    COUNT(*) FILTER (WHERE l.status = 'completed') AS completed_jobs,
    COUNT(*) FILTER (WHERE l.status = 'lost') AS lost,
    COUNT(*) FILTER (WHERE l.urgency = 'emergency') AS emergencies,
    COUNT(*) FILTER (WHERE l.source = 'phone') AS from_phone,
    COUNT(*) FILTER (WHERE l.source = 'website') AS from_website
FROM leads l
JOIN clients cl ON cl.id = l.client_id
GROUP BY l.client_id, cl.business_name;

-- Monthly revenue view
CREATE OR REPLACE VIEW monthly_revenue AS
SELECT
    DATE_TRUNC('month', i.period_start) AS month,
    COUNT(DISTINCT i.client_id) AS active_clients,
    COUNT(*) AS invoices_count,
    SUM(i.total) AS total_revenue,
    SUM(i.total) FILTER (WHERE i.status = 'paid') AS collected,
    SUM(i.total) FILTER (WHERE i.status IN ('sent', 'overdue')) AS outstanding
FROM invoices i
WHERE i.status != 'void'
GROUP BY DATE_TRUNC('month', i.period_start);


-- ============================================================================
-- SEED DATA (optional -- remove before production)
-- Uncomment to insert a test client for development.
-- ============================================================================

-- INSERT INTO clients (
--     business_name, owner_name, email, phone,
--     city, state, service_types, service_area,
--     notification_email, notification_phone,
--     service_call_fee, plan, monthly_rate, status
-- ) VALUES (
--     'ABC Heating & Cooling',
--     'John Smith',
--     'john@abcheating.com',
--     '+16025551234',
--     'Phoenix', 'AZ',
--     ARRAY['hvac', 'plumbing'],
--     'Greater Phoenix metro area',
--     'john@abcheating.com',
--     '+16025551234',
--     '$89',
--     'growth',
--     497.00,
--     'active'
-- );
