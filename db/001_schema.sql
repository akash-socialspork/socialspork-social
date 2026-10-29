-- SocialSpork dashboard schema
-- Layers: masters -> tenancy/access -> connections -> reviews/CX -> marketplace -> metrics/dashboards -> alerts

BEGIN;

CREATE EXTENSION IF NOT EXISTS citext;

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- MASTER TABLES (global lookups, seeded, same for every tenant)
-- =====================================================================

CREATE TABLE industries (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        text UNIQUE NOT NULL,          -- restaurant, hotel, healthcare, retail ...
  name        text NOT NULL,
  description text,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platforms (
  id               smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             text UNIQUE NOT NULL,     -- google, zomato, swiggy, tripadvisor ...
  name             text NOT NULL,
  category         text NOT NULL CHECK (category IN ('review','marketplace','social','listing','ota','survey')),
  supports_reviews boolean NOT NULL DEFAULT false,
  supports_replies boolean NOT NULL DEFAULT false,
  supports_orders  boolean NOT NULL DEFAULT false,
  supports_status  boolean NOT NULL DEFAULT false,  -- store online/offline
  logo_url         text,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Which platforms are relevant per industry
CREATE TABLE industry_platforms (
  industry_id smallint NOT NULL REFERENCES industries(id),
  platform_id smallint NOT NULL REFERENCES platforms(id),
  is_default  boolean NOT NULL DEFAULT true,
  PRIMARY KEY (industry_id, platform_id)
);

-- Feature modules (common core + industry packs)
CREATE TABLE modules (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        text UNIQUE NOT NULL,          -- reviews, listings, marketplace_sales ...
  name        text NOT NULL,
  scope       text NOT NULL CHECK (scope IN ('common','industry')),
  description text,
  sort_order  smallint NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true
);

CREATE TABLE industry_modules (
  industry_id smallint NOT NULL REFERENCES industries(id),
  module_id   smallint NOT NULL REFERENCES modules(id),
  is_default  boolean NOT NULL DEFAULT true,
  PRIMARY KEY (industry_id, module_id)
);

-- KPI catalogue: drives dynamic widgets; values live in metric_daily
CREATE TABLE kpi_definitions (
  id               smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             text UNIQUE NOT NULL,     -- avg_rating, online_pct, avg_prep_time ...
  name             text NOT NULL,
  module_id        smallint NOT NULL REFERENCES modules(id),
  unit             text NOT NULL CHECK (unit IN ('count','currency','percent','seconds','minutes','rating','ratio')),
  aggregation      text NOT NULL CHECK (aggregation IN ('sum','avg','weighted_avg','last','max','min')),
  higher_is_better boolean NOT NULL DEFAULT true,
  description      text,
  is_active        boolean NOT NULL DEFAULT true
);

CREATE TABLE industry_kpis (
  industry_id smallint NOT NULL REFERENCES industries(id),
  kpi_id      smallint NOT NULL REFERENCES kpi_definitions(id),
  is_default  boolean NOT NULL DEFAULT true,
  sort_order  smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (industry_id, kpi_id)
);

CREATE TABLE widget_types (
  id            smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          text UNIQUE NOT NULL,        -- kpi_card, line_chart, funnel, table ...
  name          text NOT NULL,
  config_schema jsonb NOT NULL DEFAULT '{}'
);

-- Review topic tags (industry_id NULL = applies to all industries)
CREATE TABLE review_topics (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  industry_id smallint REFERENCES industries(id),
  code        text NOT NULL,
  name        text NOT NULL,
  UNIQUE NULLS NOT DISTINCT (industry_id, code)
);

CREATE TABLE root_causes (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  industry_id smallint REFERENCES industries(id),
  code        text NOT NULL,
  name        text NOT NULL,
  UNIQUE NULLS NOT DISTINCT (industry_id, code)
);

CREATE TABLE alert_types (
  id               smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             text UNIQUE NOT NULL,     -- store_offline, negative_review, stock_out ...
  name             text NOT NULL,
  module_id        smallint REFERENCES modules(id),
  default_severity text NOT NULL DEFAULT 'medium' CHECK (default_severity IN ('low','medium','high','critical'))
);

CREATE TABLE roles (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        text UNIQUE NOT NULL,          -- super_admin, agency_admin, brand_admin, manager, viewer
  name        text NOT NULL,
  description text
);

CREATE TABLE permissions (
  id   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code text UNIQUE NOT NULL,                 -- reviews.reply, settings.manage ...
  name text NOT NULL
);

CREATE TABLE role_permissions (
  role_id       smallint NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id smallint NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- =====================================================================
-- TENANCY: tenant -> brand -> location
-- =====================================================================

CREATE TABLE tenants (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       text NOT NULL,
  slug       text UNIQUE NOT NULL,
  type       text NOT NULL DEFAULT 'direct' CHECK (type IN ('internal','agency','direct')),
  plan       text NOT NULL DEFAULT 'trial',
  settings   jsonb NOT NULL DEFAULT '{}',
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE brands (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   bigint NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  industry_id smallint NOT NULL REFERENCES industries(id),
  name        text NOT NULL,
  slug        text NOT NULL,
  logo_url    text,
  settings    jsonb NOT NULL DEFAULT '{}',
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, slug)
);

-- Per-brand module overrides on top of industry_modules defaults
CREATE TABLE brand_modules (
  brand_id   bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  module_id  smallint NOT NULL REFERENCES modules(id),
  is_enabled boolean NOT NULL DEFAULT true,
  settings   jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (brand_id, module_id)
);

CREATE TABLE locations (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id   bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  name       text NOT NULL,
  code       text,                           -- brand's own store code
  address    text,
  area       text,
  city       text,
  state      text,
  pincode    text,
  country    text NOT NULL DEFAULT 'IN',
  latitude   numeric(9,6),
  longitude  numeric(9,6),
  phone      text,
  email      citext,
  timezone   text NOT NULL DEFAULT 'Asia/Kolkata',
  attributes jsonb NOT NULL DEFAULT '{}',    -- industry-specific fields (cuisine, beds, specialties...)
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (brand_id, code)
);
CREATE INDEX ON locations (brand_id);
CREATE INDEX ON locations (city);

-- Optional grouping: region / cluster / franchisee
CREATE TABLE location_groups (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id  bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  name      text NOT NULL,
  UNIQUE (brand_id, name)
);

CREATE TABLE location_group_members (
  group_id    bigint NOT NULL REFERENCES location_groups(id) ON DELETE CASCADE,
  location_id bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, location_id)
);

-- =====================================================================
-- USERS & ACCESS
-- =====================================================================

CREATE TABLE users (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         citext UNIQUE NOT NULL,
  name          text NOT NULL,
  phone         text,
  password_hash text,
  is_active     boolean NOT NULL DEFAULT true,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Scope: tenant-wide (brand/location NULL), brand-wide (location NULL), or one location
CREATE TABLE user_access (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id     smallint NOT NULL REFERENCES roles(id),
  tenant_id   bigint NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  brand_id    bigint REFERENCES brands(id) ON DELETE CASCADE,
  location_id bigint REFERENCES locations(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (user_id, tenant_id, brand_id, location_id)
);

-- =====================================================================
-- CONNECTIONS: API accounts and per-location platform listings
-- =====================================================================

CREATE TABLE platform_connections (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id        bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  platform_id     smallint NOT NULL REFERENCES platforms(id),
  account_label   text,
  auth_type       text NOT NULL CHECK (auth_type IN ('oauth','api_key','session','partner')),
  credentials_ref text,                      -- pointer to secret store / encrypted blob, never raw secrets
  token_expires_at timestamptz,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','error','disabled')),
  last_error      text,
  last_synced_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON platform_connections (brand_id, platform_id);

-- Maps a location to its id on each platform (Google place id, Zomato res_id, Swiggy rest id)
CREATE TABLE location_listings (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  location_id    bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  platform_id    smallint NOT NULL REFERENCES platforms(id),
  connection_id  bigint REFERENCES platform_connections(id) ON DELETE SET NULL,
  external_id    text NOT NULL,
  external_url   text,
  listing_name   text,
  current_rating numeric(3,2),
  total_reviews  integer,
  current_status text CHECK (current_status IN ('online','offline','unknown')),
  status_checked_at timestamptz,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (platform_id, external_id)
);
CREATE INDEX ON location_listings (location_id);

CREATE TABLE sync_jobs (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  connection_id bigint REFERENCES platform_connections(id) ON DELETE CASCADE,
  listing_id    bigint REFERENCES location_listings(id) ON DELETE CASCADE,
  job_type      text NOT NULL,               -- reviews, orders, metrics, status, menu, payouts
  status        text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','success','failed')),
  cursor        jsonb,                       -- last synced position for incremental pulls
  records_in    integer NOT NULL DEFAULT 0,
  error         text,
  started_at    timestamptz,
  finished_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON sync_jobs (status, created_at);

-- =====================================================================
-- REVIEWS & CX (common core)
-- =====================================================================

CREATE TABLE reviews (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  listing_id         bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  location_id        bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  platform_id        smallint NOT NULL REFERENCES platforms(id),
  external_review_id text NOT NULL,
  author_name        text,
  author_external_id text,
  rating             numeric(2,1),
  title              text,
  body               text,
  language           text,
  sentiment          text CHECK (sentiment IN ('positive','neutral','negative')),
  sentiment_score    numeric(4,3),
  reviewed_at        timestamptz NOT NULL,
  reply_status       text NOT NULL DEFAULT 'pending' CHECK (reply_status IN ('pending','drafted','replied','ignored')),
  raw                jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (platform_id, external_review_id)
);
CREATE INDEX ON reviews (location_id, reviewed_at DESC);
CREATE INDEX ON reviews (reply_status) WHERE reply_status = 'pending';
CREATE INDEX ON reviews (rating);

CREATE TABLE review_topic_map (
  review_id  bigint NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  topic_id   smallint NOT NULL REFERENCES review_topics(id),
  sentiment  text CHECK (sentiment IN ('positive','neutral','negative')),
  PRIMARY KEY (review_id, topic_id)
);

CREATE TABLE reply_templates (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id  bigint NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  brand_id   bigint REFERENCES brands(id) ON DELETE CASCADE,
  name       text NOT NULL,
  min_rating numeric(2,1),
  max_rating numeric(2,1),
  body       text NOT NULL,                  -- supports {{author_name}}, {{location_name}}
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_replies (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  review_id    bigint NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  body         text NOT NULL,
  source       text NOT NULL CHECK (source IN ('manual','template','ai','platform')),
  template_id  bigint REFERENCES reply_templates(id) ON DELETE SET NULL,
  status       text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','published','failed')),
  created_by   bigint REFERENCES users(id),
  approved_by  bigint REFERENCES users(id),
  published_at timestamptz,
  error        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON review_replies (review_id);

-- Auto-reply rules per brand (e.g. AI auto-publish for 4-5 star)
CREATE TABLE auto_reply_rules (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id     bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  platform_id  smallint REFERENCES platforms(id),
  min_rating   numeric(2,1) NOT NULL,
  max_rating   numeric(2,1) NOT NULL,
  mode         text NOT NULL CHECK (mode IN ('ai','template')),
  template_id  bigint REFERENCES reply_templates(id) ON DELETE SET NULL,
  needs_approval boolean NOT NULL DEFAULT true,
  only_with_text boolean NOT NULL DEFAULT false,
  is_active    boolean NOT NULL DEFAULT true
);

CREATE TABLE tickets (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  location_id   bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  review_id     bigint REFERENCES reviews(id) ON DELETE SET NULL,
  title         text NOT NULL,
  description   text,
  priority      text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','critical')),
  status        text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
  root_cause_id smallint REFERENCES root_causes(id),
  assigned_to   bigint REFERENCES users(id),
  sla_due_at    timestamptz,
  resolved_at   timestamptz,
  created_by    bigint REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON tickets (location_id, status);

CREATE TABLE ticket_comments (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ticket_id  bigint NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  user_id    bigint REFERENCES users(id),
  body       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE competitors (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  location_id bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  platform_id smallint NOT NULL REFERENCES platforms(id),
  name        text NOT NULL,
  external_id text NOT NULL,
  UNIQUE (location_id, platform_id, external_id)
);

CREATE TABLE competitor_snapshots (
  competitor_id bigint NOT NULL REFERENCES competitors(id) ON DELETE CASCADE,
  snapshot_date date NOT NULL,
  rating        numeric(3,2),
  total_reviews integer,
  PRIMARY KEY (competitor_id, snapshot_date)
);

-- =====================================================================
-- MARKETPLACE (restaurant pack: Swiggy / Zomato)
-- =====================================================================

CREATE TABLE menu_items (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  listing_id       bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  external_item_id text NOT NULL,
  name             text NOT NULL,
  category         text,
  price            numeric(10,2),
  is_veg           boolean,
  in_stock         boolean NOT NULL DEFAULT true,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (listing_id, external_item_id)
);

CREATE TABLE stock_out_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  menu_item_id bigint NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  listing_id   bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  out_at       timestamptz NOT NULL,
  back_at      timestamptz
);
CREATE INDEX ON stock_out_events (listing_id, out_at DESC);

CREATE TABLE orders (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  listing_id        bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  location_id       bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  platform_id       smallint NOT NULL REFERENCES platforms(id),
  external_order_id text NOT NULL,
  placed_at         timestamptz NOT NULL,
  status            text NOT NULL CHECK (status IN ('placed','accepted','ready','picked_up','delivered','cancelled','rejected')),
  item_total        numeric(12,2),
  packaging_charge  numeric(12,2),
  discount_restaurant numeric(12,2),         -- discount funded by the brand
  discount_platform numeric(12,2),           -- discount funded by the platform
  tax               numeric(12,2),
  order_value       numeric(12,2),
  commission        numeric(12,2),
  platform_fee      numeric(12,2),
  other_deductions  numeric(12,2),
  expected_payout   numeric(12,2),
  prep_time_sec     integer,
  food_ready_marked_correctly boolean,       -- MFR accuracy
  is_delayed        boolean,
  is_ad_order       boolean NOT NULL DEFAULT false,
  cancelled_by      text CHECK (cancelled_by IN ('restaurant','customer','platform')),
  cancel_reason     text,
  customer_rating   numeric(2,1),
  raw               jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (platform_id, external_order_id)
);
CREATE INDEX ON orders (location_id, placed_at DESC);
CREATE INDEX ON orders (listing_id, placed_at DESC);

CREATE TABLE order_items (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id     bigint NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id bigint REFERENCES menu_items(id) ON DELETE SET NULL,
  name         text NOT NULL,
  quantity     integer NOT NULL,
  unit_price   numeric(10,2)
);

-- Store online/offline timeline
CREATE TABLE store_status_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  listing_id   bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  went_offline_at timestamptz NOT NULL,
  came_online_at  timestamptz,
  offline_reason  text,
  detected_by     text NOT NULL DEFAULT 'poller' CHECK (detected_by IN ('poller','platform','manual')),
  recovered_by    text CHECK (recovered_by IN ('auto','manual','platform')),
  recovery_attempts smallint NOT NULL DEFAULT 0,
  escalated       boolean NOT NULL DEFAULT false,
  est_revenue_loss numeric(12,2)
);
CREATE INDEX ON store_status_events (listing_id, went_offline_at DESC);

CREATE TABLE recovery_rules (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id            bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  location_id         bigint REFERENCES locations(id) ON DELETE CASCADE,  -- NULL = brand default
  check_every_minutes smallint NOT NULL DEFAULT 5,
  wait_before_recover_minutes smallint NOT NULL DEFAULT 10,
  max_attempts        smallint NOT NULL DEFAULT 3,
  auto_recover        boolean NOT NULL DEFAULT false,
  is_excluded         boolean NOT NULL DEFAULT false,
  escalate_to         jsonb NOT NULL DEFAULT '[]',  -- [{channel:'whatsapp', to:'+91...'}]
  UNIQUE NULLS NOT DISTINCT (brand_id, location_id)
);

-- Settlement / reconciliation
CREATE TABLE payouts (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  listing_id      bigint NOT NULL REFERENCES location_listings(id) ON DELETE CASCADE,
  period_start    date NOT NULL,
  period_end      date NOT NULL,
  expected_amount numeric(14,2),
  actual_amount   numeric(14,2),
  utr             text,
  paid_on         date,
  raw             jsonb,
  UNIQUE (listing_id, period_start, period_end)
);

CREATE TABLE reconciliation_exceptions (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payout_id   bigint REFERENCES payouts(id) ON DELETE CASCADE,
  order_id    bigint REFERENCES orders(id) ON DELETE CASCADE,
  type        text NOT NULL,                 -- commission_mismatch, missing_order, excess_deduction ...
  amount      numeric(12,2),
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','claimed','recovered','written_off')),
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- METRICS (dynamic, KPI-driven) & DASHBOARDS
-- =====================================================================

-- One row per location/platform/KPI/day. platform_id NULL = all platforms combined.
CREATE TABLE metric_daily (
  location_id bigint NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  platform_id smallint REFERENCES platforms(id),
  kpi_id      smallint NOT NULL REFERENCES kpi_definitions(id),
  metric_date date NOT NULL,
  value       numeric(16,4) NOT NULL,
  weight      numeric(16,4),                 -- for weighted averages (e.g. order count)
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (location_id, platform_id, kpi_id, metric_date)
);
CREATE INDEX ON metric_daily (kpi_id, metric_date);

CREATE TABLE dashboards (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id   bigint REFERENCES brands(id) ON DELETE CASCADE,  -- NULL = industry template
  industry_id smallint REFERENCES industries(id),
  module_id  smallint REFERENCES modules(id),
  name       text NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_by bigint REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE dashboard_widgets (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dashboard_id   bigint NOT NULL REFERENCES dashboards(id) ON DELETE CASCADE,
  widget_type_id smallint NOT NULL REFERENCES widget_types(id),
  title          text,
  kpi_ids        smallint[] NOT NULL DEFAULT '{}',
  config         jsonb NOT NULL DEFAULT '{}',  -- filters, comparison period, colours
  position       jsonb NOT NULL DEFAULT '{"x":0,"y":0,"w":3,"h":2}'
);

-- =====================================================================
-- ALERTS & NOTIFICATIONS
-- =====================================================================

CREATE TABLE alert_rules (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id      bigint NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  alert_type_id smallint NOT NULL REFERENCES alert_types(id),
  conditions    jsonb NOT NULL DEFAULT '{}',   -- e.g. {"max_rating":2} or {"offline_minutes":15}
  channels      jsonb NOT NULL DEFAULT '[]',   -- [{channel:'email', to:'...'}]
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE alerts (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_type_id smallint NOT NULL REFERENCES alert_types(id),
  rule_id       bigint REFERENCES alert_rules(id) ON DELETE SET NULL,
  location_id   bigint REFERENCES locations(id) ON DELETE CASCADE,
  listing_id    bigint REFERENCES location_listings(id) ON DELETE CASCADE,
  severity      text NOT NULL CHECK (severity IN ('low','medium','high','critical')),
  message       text NOT NULL,
  payload       jsonb,
  status        text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  resolved_at   timestamptz
);
CREATE INDEX ON alerts (location_id, created_at DESC);

CREATE TABLE notifications_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_id   bigint REFERENCES alerts(id) ON DELETE CASCADE,
  channel    text NOT NULL CHECK (channel IN ('email','whatsapp','sms','in_app')),
  recipient  text NOT NULL,
  status     text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','failed')),
  error      text,
  sent_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     bigint REFERENCES users(id),
  tenant_id   bigint REFERENCES tenants(id),
  action      text NOT NULL,
  entity_type text NOT NULL,
  entity_id   bigint,
  changes     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- updated_at triggers
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.columns
           WHERE table_schema = 'public' AND column_name = 'updated_at'
  LOOP
    EXECUTE format('CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
  END LOOP;
END $$;

COMMIT;
