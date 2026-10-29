-- Master data seed. Safe to re-run (ON CONFLICT DO NOTHING).

BEGIN;

INSERT INTO industries (code, name) VALUES
  ('restaurant',  'Restaurants & QSR'),
  ('cafe_bakery', 'Cafes & Bakeries'),
  ('hotel',       'Hotels & Hospitality'),
  ('healthcare',  'Hospitals & Clinics'),
  ('retail',      'Retail Stores'),
  ('automobile',  'Automobile Dealerships'),
  ('salon_spa',   'Salons & Spas'),
  ('education',   'Education & Coaching'),
  ('bfsi',        'Banks & Financial Services'),
  ('real_estate', 'Real Estate')
ON CONFLICT (code) DO NOTHING;

INSERT INTO platforms (code, name, category, supports_reviews, supports_replies, supports_orders, supports_status) VALUES
  ('google',      'Google Business Profile', 'review',      true,  true,  false, false),
  ('zomato',      'Zomato',                  'marketplace', true,  true,  true,  true),
  ('swiggy',      'Swiggy',                  'marketplace', true,  true,  true,  true),
  ('magicpin',    'magicpin',                'marketplace', true,  false, true,  true),
  ('eazydiner',   'EazyDiner',               'review',      true,  false, false, false),
  ('tripadvisor', 'Tripadvisor',             'review',      true,  true,  false, false),
  ('booking',     'Booking.com',             'ota',         true,  true,  false, false),
  ('makemytrip',  'MakeMyTrip',              'ota',         true,  true,  false, false),
  ('goibibo',     'Goibibo',                 'ota',         true,  true,  false, false),
  ('agoda',       'Agoda',                   'ota',         true,  true,  false, false),
  ('practo',      'Practo',                  'review',      true,  false, false, false),
  ('justdial',    'Justdial',                'listing',     true,  false, false, false),
  ('facebook',    'Facebook',                'social',      true,  true,  false, false),
  ('instagram',   'Instagram',               'social',      false, true,  false, false),
  ('amazon',      'Amazon',                  'marketplace', true,  false, true,  false),
  ('flipkart',    'Flipkart',                'marketplace', true,  false, true,  false),
  ('survey',      'SocialSpork Survey',      'survey',      true,  false, false, false)
ON CONFLICT (code) DO NOTHING;

INSERT INTO industry_platforms (industry_id, platform_id)
SELECT i.id, p.id FROM (VALUES
  ('restaurant','google'),('restaurant','zomato'),('restaurant','swiggy'),('restaurant','magicpin'),
  ('restaurant','eazydiner'),('restaurant','facebook'),('restaurant','instagram'),('restaurant','survey'),
  ('cafe_bakery','google'),('cafe_bakery','zomato'),('cafe_bakery','swiggy'),('cafe_bakery','instagram'),('cafe_bakery','survey'),
  ('hotel','google'),('hotel','tripadvisor'),('hotel','booking'),('hotel','makemytrip'),('hotel','goibibo'),('hotel','agoda'),('hotel','facebook'),('hotel','survey'),
  ('healthcare','google'),('healthcare','practo'),('healthcare','justdial'),('healthcare','facebook'),('healthcare','survey'),
  ('retail','google'),('retail','justdial'),('retail','amazon'),('retail','flipkart'),('retail','facebook'),('retail','instagram'),('retail','survey'),
  ('automobile','google'),('automobile','justdial'),('automobile','facebook'),('automobile','survey'),
  ('salon_spa','google'),('salon_spa','justdial'),('salon_spa','instagram'),('salon_spa','survey'),
  ('education','google'),('education','justdial'),('education','facebook'),('education','survey'),
  ('bfsi','google'),('bfsi','justdial'),('bfsi','survey'),
  ('real_estate','google'),('real_estate','facebook'),('real_estate','survey')
) v(ind, plat)
JOIN industries i ON i.code = v.ind
JOIN platforms  p ON p.code = v.plat
ON CONFLICT DO NOTHING;

INSERT INTO modules (code, name, scope, sort_order, description) VALUES
  ('overview',              'Overview',                 'common',   1,  'Cross-platform summary'),
  ('reviews',               'Reviews',                  'common',   2,  'Unified reviews inbox and analytics'),
  ('ai_replies',            'AI Replies',               'common',   3,  'AI-drafted and auto-published replies'),
  ('listings',              'Listings',                 'common',   4,  'Google listings and bulk updates'),
  ('reports',               'Reports',                  'common',   5,  'Scheduled and on-demand reports'),
  ('tickets',               'Tickets',                  'common',   6,  'Service tickets and root cause analysis'),
  ('competitors',           'Competitors',              'common',   7,  'Location-based competitor tracking'),
  ('surveys',               'Surveys',                  'common',   8,  'QR / SMS / WhatsApp feedback'),
  ('social',                'Social',                   'common',   9,  'Mentions, posts and messages'),
  ('alerts',                'Alerts',                   'common',   10, 'Alert rules and notifications'),
  ('marketplace_sales',     'Sales Performance',        'industry', 20, 'Orders, revenue and channel split'),
  ('marketplace_ops',       'Delivery & Operations',    'industry', 21, 'Prep time, MFR, delays, cancellations'),
  ('marketplace_funnel',    'Customer Funnel',          'industry', 22, 'Impressions to orders'),
  ('marketplace_ads',       'Ads Performance',          'industry', 23, 'Ad spend, sales and ROI'),
  ('marketplace_discounts', 'Discounts & Offers',       'industry', 24, 'Discount impact and leakage'),
  ('store_uptime',          'Store Uptime',             'industry', 25, 'Online status, downtime and auto recovery'),
  ('stock_outs',            'Stock-outs',               'industry', 26, 'Item availability monitoring'),
  ('reconciliation',        'Reconciliation',           'industry', 27, 'Payouts, fees and claimable amounts')
ON CONFLICT (code) DO NOTHING;

-- Every industry gets all common modules
INSERT INTO industry_modules (industry_id, module_id)
SELECT i.id, m.id FROM industries i CROSS JOIN modules m WHERE m.scope = 'common'
ON CONFLICT DO NOTHING;

-- Food industries get the marketplace pack
INSERT INTO industry_modules (industry_id, module_id)
SELECT i.id, m.id FROM industries i CROSS JOIN modules m
WHERE m.scope = 'industry' AND i.code IN ('restaurant','cafe_bakery')
ON CONFLICT DO NOTHING;

-- Retail gets sales + reconciliation (Amazon/Flipkart)
INSERT INTO industry_modules (industry_id, module_id)
SELECT i.id, m.id FROM industries i CROSS JOIN modules m
WHERE i.code = 'retail' AND m.code IN ('marketplace_sales','reconciliation')
ON CONFLICT DO NOTHING;

INSERT INTO kpi_definitions (code, name, module_id, unit, aggregation, higher_is_better)
SELECT v.code, v.name, m.id, v.unit, v.agg, v.hib FROM (VALUES
  -- reviews (common)
  ('avg_rating',             'Average Rating',              'reviews',               'rating',   'weighted_avg', true),
  ('review_count',           'New Reviews',                 'reviews',               'count',    'sum',          true),
  ('positive_review_pct',    'Positive Reviews %',          'reviews',               'percent',  'weighted_avg', true),
  ('negative_review_count',  'Negative Reviews',            'reviews',               'count',    'sum',          false),
  ('response_rate',          'Response Rate',               'reviews',               'percent',  'weighted_avg', true),
  ('avg_response_time',      'Avg Response Time',           'reviews',               'minutes',  'avg',          false),
  ('listing_rating',         'Platform Rating',             'listings',              'rating',   'last',         true),
  ('total_reviews',          'Total Reviews on Platform',   'listings',              'count',    'last',         true),
  ('open_tickets',           'Open Tickets',                'tickets',               'count',    'last',         false),
  ('survey_responses',       'Survey Responses',            'surveys',               'count',    'sum',          true),
  ('nps',                    'NPS',                         'surveys',               'ratio',    'weighted_avg', true),
  -- sales
  ('delivered_orders',       'Delivered Orders',            'marketplace_sales',     'count',    'sum',          true),
  ('gross_revenue',          'Gross Revenue',               'marketplace_sales',     'currency', 'sum',          true),
  ('net_revenue',            'Net Revenue',                 'marketplace_sales',     'currency', 'sum',          true),
  ('avg_order_value',        'Avg Order Value',             'marketplace_sales',     'currency', 'weighted_avg', true),
  -- operations
  ('online_pct',             'Store Online %',              'marketplace_ops',       'percent',  'weighted_avg', true),
  ('avg_prep_time',          'Avg Kitchen Prep Time',       'marketplace_ops',       'seconds',  'weighted_avg', false),
  ('mfr_accuracy',           'Food Ready Accuracy (MFR)',   'marketplace_ops',       'percent',  'weighted_avg', true),
  ('delayed_orders_pct',     'Delayed Orders %',            'marketplace_ops',       'percent',  'weighted_avg', false),
  ('cancellation_rate',      'Cancellation Rate',           'marketplace_ops',       'percent',  'weighted_avg', false),
  ('cancellation_loss',      'Revenue Lost to Cancellations','marketplace_ops',      'currency', 'sum',          false),
  -- funnel
  ('impressions',            'Impressions',                 'marketplace_funnel',    'count',    'sum',          true),
  ('menu_views',             'Menu Views',                  'marketplace_funnel',    'count',    'sum',          true),
  ('add_to_cart',            'Add to Cart',                 'marketplace_funnel',    'count',    'sum',          true),
  ('funnel_orders',          'Orders Placed',               'marketplace_funnel',    'count',    'sum',          true),
  ('menu_to_order_pct',      'Menu to Order Conversion',    'marketplace_funnel',    'percent',  'weighted_avg', true),
  -- ads
  ('ad_spend',               'Ad Spend',                    'marketplace_ads',       'currency', 'sum',          false),
  ('ad_sales',               'Ad Sales',                    'marketplace_ads',       'currency', 'sum',          true),
  ('ad_impressions',         'Ad Impressions',              'marketplace_ads',       'count',    'sum',          true),
  ('ad_menu_visits',         'Ad Menu Visits',              'marketplace_ads',       'count',    'sum',          true),
  ('ad_orders',              'Ad Orders',                   'marketplace_ads',       'count',    'sum',          true),
  ('ad_roi',                 'Ad ROI',                      'marketplace_ads',       'ratio',    'weighted_avg', true),
  -- discounts
  ('discount_given',         'Discounts Given',             'marketplace_discounts', 'currency', 'sum',          false),
  ('discount_gross_sales',   'Gross Sales from Discounts',  'marketplace_discounts', 'currency', 'sum',          true),
  ('discounted_orders',      'Orders with Discounts',       'marketplace_discounts', 'count',    'sum',          true),
  ('discount_per_order',     'Discount per Order',          'marketplace_discounts', 'currency', 'weighted_avg', false),
  ('discount_pct_revenue',   'Discount % of Revenue',       'marketplace_discounts', 'percent',  'weighted_avg', false),
  -- uptime
  ('offline_events',         'Offline Events',              'store_uptime',          'count',    'sum',          false),
  ('avg_downtime',           'Avg Downtime',                'store_uptime',          'minutes',  'avg',          false),
  ('downtime_revenue_loss',  'Est. Revenue Loss (Downtime)','store_uptime',          'currency', 'sum',          false),
  ('auto_recovery_pct',      'Auto-Recovery Success %',     'store_uptime',          'percent',  'weighted_avg', true),
  -- stock
  ('stock_out_items',        'Items Out of Stock',          'stock_outs',            'count',    'sum',          false),
  -- reconciliation
  ('payout_discrepancy',     'Payout Discrepancy',          'reconciliation',        'currency', 'sum',          false),
  ('claimable_amount',       'Claimable Amount',            'reconciliation',        'currency', 'sum',          true),
  ('take_rate',              'Commission Take Rate',        'reconciliation',        'percent',  'weighted_avg', false)
) v(code, name, module, unit, agg, hib)
JOIN modules m ON m.code = v.module
ON CONFLICT (code) DO NOTHING;

-- Industries get KPIs for the modules they have
INSERT INTO industry_kpis (industry_id, kpi_id, sort_order)
SELECT im.industry_id, k.id, k.id FROM industry_modules im
JOIN kpi_definitions k ON k.module_id = im.module_id
ON CONFLICT DO NOTHING;

INSERT INTO widget_types (code, name) VALUES
  ('kpi_card',      'KPI Card'),
  ('line_chart',    'Trend Line'),
  ('bar_chart',     'Bar Chart'),
  ('stacked_bar',   'Stacked Bar'),
  ('donut',         'Donut / Split'),
  ('funnel',        'Funnel'),
  ('table',         'Table'),
  ('leaderboard',   'Location Leaderboard'),
  ('heatmap',       'Heatmap'),
  ('map',           'Location Map'),
  ('review_feed',   'Review Feed'),
  ('status_grid',   'Store Status Grid')
ON CONFLICT (code) DO NOTHING;

INSERT INTO review_topics (industry_id, code, name)
SELECT i.id, v.code, v.name FROM (VALUES
  (NULL, 'service',      'Service'),
  (NULL, 'staff',        'Staff Behaviour'),
  (NULL, 'price',        'Price / Value'),
  (NULL, 'cleanliness',  'Cleanliness'),
  (NULL, 'ambience',     'Ambience'),
  (NULL, 'wait_time',    'Wait Time'),
  ('restaurant', 'food_taste',   'Food Taste'),
  ('restaurant', 'food_quality', 'Food Quality'),
  ('restaurant', 'portion',      'Portion Size'),
  ('restaurant', 'packaging',    'Packaging'),
  ('restaurant', 'delivery',     'Delivery'),
  ('restaurant', 'wrong_order',  'Wrong / Missing Item'),
  ('hotel',      'room',         'Room'),
  ('hotel',      'check_in',     'Check-in'),
  ('hotel',      'breakfast',    'Breakfast'),
  ('hotel',      'location',     'Location'),
  ('healthcare', 'doctor',       'Doctor'),
  ('healthcare', 'billing',      'Billing'),
  ('healthcare', 'appointment',  'Appointment'),
  ('retail',     'product',      'Product Availability'),
  ('retail',     'returns',      'Returns / Exchange'),
  ('automobile', 'test_drive',   'Test Drive'),
  ('automobile', 'servicing',    'Servicing')
) v(ind, code, name)
LEFT JOIN industries i ON i.code = v.ind
ON CONFLICT DO NOTHING;

INSERT INTO root_causes (industry_id, code, name)
SELECT i.id, v.code, v.name FROM (VALUES
  (NULL, 'staff_training',  'Staff Training'),
  (NULL, 'process_gap',     'Process Gap'),
  (NULL, 'understaffed',    'Understaffed'),
  (NULL, 'pricing',         'Pricing'),
  (NULL, 'other',           'Other'),
  ('restaurant', 'kitchen_delay',   'Kitchen Delay'),
  ('restaurant', 'recipe_variance', 'Recipe Variance'),
  ('restaurant', 'packaging_issue', 'Packaging Issue'),
  ('restaurant', 'rider_issue',     'Delivery Partner Issue'),
  ('restaurant', 'stock_out',       'Stock-out')
) v(ind, code, name)
LEFT JOIN industries i ON i.code = v.ind
ON CONFLICT DO NOTHING;

INSERT INTO alert_types (code, name, module_id, default_severity)
SELECT v.code, v.name, m.id, v.sev FROM (VALUES
  ('negative_review',    'Negative Review Received',  'reviews',         'high'),
  ('unreplied_review',   'Review Unreplied (SLA)',    'reviews',         'medium'),
  ('rating_drop',        'Rating Dropped',            'listings',        'high'),
  ('listing_changed',    'Listing Edited Externally', 'listings',        'medium'),
  ('ticket_sla_breach',  'Ticket SLA Breached',       'tickets',         'high'),
  ('store_offline',      'Store Went Offline',        'store_uptime',    'critical'),
  ('recovery_failed',    'Auto-Recovery Failed',      'store_uptime',    'critical'),
  ('stock_out',          'Item Out of Stock',         'stock_outs',      'medium'),
  ('high_prep_time',     'High Prep Time',            'marketplace_ops', 'medium'),
  ('high_cancellations', 'High Cancellations',        'marketplace_ops', 'high'),
  ('payout_mismatch',    'Payout Mismatch',           'reconciliation',  'high'),
  ('connection_error',   'Platform Connection Error', 'alerts',          'high')
) v(code, name, module, sev)
JOIN modules m ON m.code = v.module
ON CONFLICT (code) DO NOTHING;

INSERT INTO roles (code, name, description) VALUES
  ('super_admin',  'Super Admin',  'SocialSpork staff, all tenants'),
  ('tenant_admin', 'Tenant Admin', 'Full access within a tenant'),
  ('brand_admin',  'Brand Admin',  'Full access within a brand'),
  ('manager',      'Manager',      'Reply, manage tickets for assigned locations'),
  ('viewer',       'Viewer',       'Read-only')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions (code, name) VALUES
  ('dashboard.view',     'View dashboards'),
  ('dashboard.edit',     'Edit dashboards'),
  ('reviews.view',       'View reviews'),
  ('reviews.reply',      'Reply to reviews'),
  ('reviews.approve',    'Approve AI replies'),
  ('listings.edit',      'Edit listings'),
  ('tickets.manage',     'Manage tickets'),
  ('marketplace.view',   'View marketplace data'),
  ('marketplace.control','Switch stores online/offline'),
  ('finance.view',       'View payouts and reconciliation'),
  ('connections.manage', 'Manage platform connections'),
  ('users.manage',       'Manage users'),
  ('settings.manage',    'Manage settings')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.code IN ('super_admin','tenant_admin')
   OR (r.code = 'brand_admin' AND p.code <> 'users.manage')
   OR (r.code = 'manager' AND p.code IN ('dashboard.view','reviews.view','reviews.reply','tickets.manage','marketplace.view'))
   OR (r.code = 'viewer'  AND p.code IN ('dashboard.view','reviews.view','marketplace.view'))
ON CONFLICT DO NOTHING;

COMMIT;
