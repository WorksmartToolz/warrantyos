-- 024_tenant_holidays.sql
--
-- Per-tenant holiday calendar. The platform's business-day math skips Saturdays,
-- Sundays, and any date in this table for the tenant in question.
--
-- Locked source: Decision 25.3 (Phase 3 decisions log) -- the table's six-column
-- shape, the platform-seeds-then-tenant-owns philosophy, and the business-day
-- rule ("skip Sat/Sun and any tenant_holidays date"). Referenced by the arch
-- ref's ALA System "Response window, overdue flag, and re-issue" subsection.
--
-- WHY THIS IS ITS OWN MIGRATION, SEPARATE FROM THE ALA TABLES (025):
-- tenant_holidays carries NO FK to any ALA table and no ALA table carries an FK
-- to it -- the relationship is app-layer business-day math only. That is the
-- 018/019 "independent siblings" case, which got separate files, rather than the
-- 022 "one section with intra-section FKs" case, which was bundled. ALA is
-- merely this table's first consumer; the calendar is general infrastructure and
-- any future business-day window reads it.
--
-- WHY 25.3 EXTENDS THE TENANT-EDITABLE DEFAULTS PHILOSOPHY BUT NOT ITS
-- MECHANICS: Decision 17's principle fits exactly -- platform seeds at
-- provisioning, tenant owns forever after, no propagation (17.A.3). But 17's
-- FK + Snapshot lookup-table mechanism does NOT fit, because no operational
-- table references a holiday by FK. 25.3 says this outright. Hence: no
-- lock_tier column, no is_system flag, no protection trigger, no value/label
-- pair, no sort_order. Plain rows the tenant owns outright. A tenant can delete
-- every row in this table and the platform is fine with that -- business-day
-- math simply skips weekends only.
--
-- THE SEED IS A STARTING DEFAULT, NOT A MODEL OF WHAT WARRANTORS OBSERVE.
-- No two companies recognize the same holiday set. Some close Good Friday; some
-- skip Columbus Day; some add company-specific days; some observe the Friday
-- before a Saturday holiday, others the Monday after, others neither, others
-- both. The platform cannot know, and does not assert. What it seeds is the
-- U.S. federal list -- the one defensible starting point for U.S. business --
-- and every tenant edits from there on day one. The schema deliberately offers
-- nothing that resists editing: no lock tier, no protection, no is_system.
--
-- OBSERVED-SHIFT RULE IS APPLIED IN THE SEED (Andre's call, Chat 17).
-- FIVE of the eleven federal holidays are fixed-date (Jan 1, Jun 19, Jul 4,
-- Nov 11, Dec 25) and can land on a weekend. The federal rule -- Saturday shifts
-- to the preceding Friday, Sunday shifts to the following Monday -- is what OPM
-- publishes and what most U.S. warrantors actually follow, so seeding the
-- shifted date means most tenants edit nothing. The alternative (seed the
-- unshifted calendar date) would hand every tenant the same correction to make.
-- Tenant policy variance is absorbed by the table itself without any schema
-- support: holiday_date stores a concrete observed date, so a tenant taking the
-- Monday instead of the Friday edits one row, a tenant taking both adds a row,
-- and a tenant taking neither deletes. The remaining SIX are Nth-weekday
-- holidays (MLK, Washington's Birthday, Memorial, Labor, Columbus,
-- Thanksgiving) and never need the shift -- they fall on a Monday or Thursday
-- by construction.
--
-- WHY A FUNCTION AND NOT A LIST OF LITERAL DATES:
-- A hand-written block of dates would need an end year, and an end year fails
-- SILENTLY -- business-day math would simply stop skipping holidays past the
-- cliff, producing wrong fires_at timestamps with no error and no alert. Nobody
-- would be looking. federal_holidays_for_year(int) removes the cliff: the rule
-- is encoded once, version-controlled, and answers for any year.
--
-- The function is IMMUTABLE and reads no tables -- pure computation from a year
-- integer. It is not a trigger, so Decision 17.A.6's "no PostgreSQL triggers at
-- v1" restraint does not bar it; that rule is about triggers, and this is a
-- callable. Conventions match 011's protect_system_warranty_types(): plpgsql,
-- set search_path = public, NO security definer (migration 002's hardening
-- precedent).
--
-- BACKFILL HORIZON AND THE ROLLING TOP-UP -- A REAL, RECORDED DEPENDENCY:
-- This migration backfills BACKFILL_FIRST_YEAR..BACKFILL_LAST_YEAR (2026-2036)
-- for tenants that predate it -- a one-time bootstrap, exactly the 018/019
-- precedent, NOT the ongoing platform-to-tenant propagation 17.A.3 forbids.
--
-- That range is a starting horizon, not a cap: the intended mechanic is a
-- rolling annual top-up that calls this same function to extend every tenant's
-- list forward. The top-up CANNOT land here -- it needs pg_cron, and pg_cron
-- enablement plus the cron handler function are separate Phase 3 work not yet
-- built (clock_events (013) is likewise the table only). Until that job lands,
-- the horizon is literally what this backfill wrote. That is a real dependency
-- and is recorded as such rather than assumed away. Because the function exists
-- and is version-controlled, the top-up is a schedule calling a callable, not a
-- redesign.
--
-- New-tenant seeding is an app-layer provisioning step calling this same
-- function -- the same convention as tenant_id_sequences (009) and the
-- warranty_types anchor rows (011), and what 25.3 means by "at provisioning".
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--   - No lock_tier, no is_system, no protection trigger. 25.3 explicitly does
--     NOT apply Decision 17's mechanics, only its philosophy. Tenants own these
--     rows outright; nothing may resist a tenant deleting or editing any row.
--   - No unique on (tenant_id, holiday_date). Not in the locked sketch. A tenant
--     may legitimately hold two rows on one date (e.g. a federal holiday and a
--     company day that coincide), and business-day math is set-membership --
--     duplicates are harmless. Uniqueness would also make the backfill's
--     where-not-exists guard load-bearing in a way the locked text never asks
--     for.
--   - No FK to anything but tenants. No operational table references a holiday
--     by FK (25.3); the relationship to ALA is app-layer math.
--   - No deleted_at. Holidays are not audit artifacts. A tenant removing a
--     holiday it does not observe should remove it, not tombstone it. Not in the
--     locked sketch.
--   - No year column. holiday_date carries the year; a separate column would
--     duplicate it and could drift.
--   - No recurrence/rule column. The recurrence lives in
--     federal_holidays_for_year(); the table stores concrete observed dates,
--     which is what makes tenant policy variance expressible without schema
--     support.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - Business-day math (skip Sat/Sun and any tenant_holidays date for that
--     tenant) runs at the moment fires_at is computed, producing a concrete
--     stored timestamp -- the same convention as every other clock event (25.3).
--   - New-tenant provisioning seeds this table from
--     federal_holidays_for_year().
--   - The rolling top-up extends each tenant's horizon annually (pending
--     pg_cron).

-- ---------------------------------------------------------------------------
-- tenant_holidays
-- ---------------------------------------------------------------------------
create table public.tenant_holidays (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id),
                -- denormalized per Standard RLS Pattern.
  holiday_date  date not null,
                -- the concrete OBSERVED date the tenant is closed. Not the
                --   nominal calendar date of the holiday: if a tenant observes
                --   July 4th on Friday July 3rd, this column holds 2026-07-03.
                --   Storing observed dates rather than holiday rules is what
                --   lets tenant policy variance be expressed by editing rows.
  label         text not null,
                -- human-readable name. Tenant-editable like everything else
                --   here; the seed supplies the federal names as a starting
                --   point.
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index tenant_holidays_tenant_id_idx
  on public.tenant_holidays (tenant_id);
create index tenant_holidays_tenant_date_idx
  on public.tenant_holidays (tenant_id, holiday_date);
  -- the business-day math lookup path: "is this date a holiday for this
  -- tenant?" -- called in a loop while walking forward N business days from a
  -- window's start, on every ALA creation and re-issue.
comment on table public.tenant_holidays is
  'Per-tenant holiday calendar (Decision 25.3). Business-day math skips '
  'Saturdays, Sundays, and any date in this table for the tenant in question. '
  'Extends the Tenant-Editable Defaults PHILOSOPHY (platform seeds at '
  'provisioning, tenant owns forever after, no propagation -- 17.A.3) but '
  'deliberately NOT its mechanics: no lock_tier, no is_system, no protection '
  'trigger, because no operational table references a holiday by FK. The seed '
  'is a STARTING DEFAULT, not a model of what warrantors observe -- no two '
  'companies recognize the same set, and every tenant edits from day one. A '
  'tenant may delete every row here; business-day math then skips weekends '
  'only.';
comment on column public.tenant_holidays.holiday_date is
  'The concrete OBSERVED date the tenant is closed -- not the nominal calendar '
  'date of the holiday. The seed applies the federal observed-shift rule '
  '(Saturday -> preceding Friday, Sunday -> following Monday) to the four '
  'fixed-date holidays, because that is what OPM publishes and what most U.S. '
  'warrantors follow, so most tenants edit nothing. Tenants who differ edit '
  'rows: taking the Monday instead of the Friday changes this value, taking '
  'both adds a row, taking neither deletes. Storing observed dates rather than '
  'holiday rules is precisely what makes that variance expressible without any '
  'schema support.';

-- ---------------------------------------------------------------------------
-- federal_holidays_for_year(int)
--
-- Returns the eleven U.S. federal holidays for any year, with the observed-shift
-- rule applied to the four fixed-date holidays. Pure computation: reads no
-- tables, so IMMUTABLE.
--
-- Encoding the rule once removes the silent-expiry cliff a literal date list
-- would carry. Not a trigger -- 17.A.6's no-triggers-at-v1 restraint does not
-- apply. Conventions per 011: plpgsql, set search_path = public, no security
-- definer.
--
-- YEAR-BOUNDARY EDGE CASE -- CORRECT, NOT A BUG. When January 1 falls on a
-- Saturday the observed date shifts BACKWARD into the previous year, so
-- federal_holidays_for_year(2028) returns 2027-12-31 for New Year's Day. That
-- is the real observed date -- OPM publishes it that way and the tenant really
-- is closed that Friday -- so it is returned as-is rather than suppressed or
-- clamped. Consequence: "year N's holidays" may contain a date outside year N.
-- Callers must not assume otherwise. The where-not-exists guard on the backfill
-- makes the resulting overlap at range boundaries harmless.
-- ---------------------------------------------------------------------------
create or replace function public.federal_holidays_for_year(p_year integer)
returns table (holiday_date date, label text)
language plpgsql
immutable
set search_path = public
as $$
declare
  v_date  date;
  v_label text;
begin
  if p_year is null or p_year < 1900 or p_year > 9999 then
    raise exception 'federal_holidays_for_year: year out of range: %', p_year;
  end if;

  -- Fixed-date holidays, observed-shift rule applied.
  -- Saturday (dow 6) -> preceding Friday; Sunday (dow 0) -> following Monday.
  -- Five of the eleven are fixed-date: these four plus Veterans Day (below).
  for v_date, v_label in
    select d, l from (values
      (make_date(p_year,  1,  1), 'New Year''s Day'),
      (make_date(p_year,  6, 19), 'Juneteenth National Independence Day'),
      (make_date(p_year,  7,  4), 'Independence Day'),
      (make_date(p_year, 12, 25), 'Christmas Day')
    ) as t(d, l)
  loop
    holiday_date := case extract(dow from v_date)
                      when 6 then v_date - 1   -- Saturday -> Friday
                      when 0 then v_date + 1   -- Sunday   -> Monday
                      else v_date
                    end;
    label := v_label;
    return next;
  end loop;

  -- Nth-weekday holidays. These always fall on a Monday or Thursday by
  -- construction, so the observed-shift rule never applies to them.
  --   third Monday of January
  holiday_date := public.nth_weekday_of_month(p_year, 1, 1, 3);
  label := 'Birthday of Martin Luther King, Jr.';
  return next;

  --   third Monday of February
  holiday_date := public.nth_weekday_of_month(p_year, 2, 1, 3);
  label := 'Washington''s Birthday';
  return next;

  --   LAST Monday of May
  holiday_date := public.last_weekday_of_month(p_year, 5, 1);
  label := 'Memorial Day';
  return next;

  --   first Monday of September
  holiday_date := public.nth_weekday_of_month(p_year, 9, 1, 1);
  label := 'Labor Day';
  return next;

  --   second Monday of October
  holiday_date := public.nth_weekday_of_month(p_year, 10, 1, 2);
  label := 'Columbus Day';
  return next;

  --   fourth Thursday of November
  holiday_date := public.nth_weekday_of_month(p_year, 11, 4, 4);
  label := 'Thanksgiving Day';
  return next;

  -- Veterans Day, November 11 -- fixed-date, so the shift rule applies. Grouped
  -- here rather than in the loop above only because it was added to the federal
  -- list separately; the treatment is identical.
  v_date := make_date(p_year, 11, 11);
  holiday_date := case extract(dow from v_date)
                    when 6 then v_date - 1
                    when 0 then v_date + 1
                    else v_date
                  end;
  label := 'Veterans Day';
  return next;

  return;
end;
$$;
comment on function public.federal_holidays_for_year(integer) is
  'Returns the eleven U.S. federal holidays for any year, with the federal '
  'observed-shift rule (Saturday -> preceding Friday, Sunday -> following '
  'Monday) applied to the five fixed-date holidays. Pure computation, reads no '
  'tables, IMMUTABLE. Encoding the rule once rather than enumerating literal '
  'dates removes the silent-expiry cliff a bounded date list would carry -- '
  'business-day math would otherwise stop skipping holidays past the cliff with '
  'no error and no alert. Called by this migration''s backfill, by app-layer '
  'new-tenant provisioning (Decision 25.3''s "at provisioning"), and by the '
  'rolling annual top-up once pg_cron lands. The result is a STARTING DEFAULT '
  'that tenants edit -- it is not a claim about what any warrantor observes.';

-- ---------------------------------------------------------------------------
-- nth_weekday_of_month(year, month, dow, n) -- helper
--   dow: 0 = Sunday .. 6 = Saturday, matching extract(dow from date).
-- ---------------------------------------------------------------------------
create or replace function public.nth_weekday_of_month(
  p_year integer, p_month integer, p_dow integer, p_n integer
)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_first date := make_date(p_year, p_month, 1);
  v_offset integer;
begin
  -- days from the 1st to the first occurrence of p_dow
  v_offset := (p_dow - extract(dow from v_first)::integer + 7) % 7;
  return v_first + v_offset + (p_n - 1) * 7;
end;
$$;
comment on function public.nth_weekday_of_month(integer, integer, integer, integer) is
  'Helper for federal_holidays_for_year(): the Nth occurrence of a given weekday '
  'in a given month. dow follows extract(dow from date): 0 = Sunday .. 6 = '
  'Saturday. Pure computation, IMMUTABLE.';

-- ---------------------------------------------------------------------------
-- last_weekday_of_month(year, month, dow) -- helper
--   Memorial Day is the LAST Monday of May, not the Nth.
-- ---------------------------------------------------------------------------
create or replace function public.last_weekday_of_month(
  p_year integer, p_month integer, p_dow integer
)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_last date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_back integer;
begin
  -- days back from the last day of the month to the preceding p_dow
  v_back := (extract(dow from v_last)::integer - p_dow + 7) % 7;
  return v_last - v_back;
end;
$$;
comment on function public.last_weekday_of_month(integer, integer, integer) is
  'Helper for federal_holidays_for_year(): the last occurrence of a given '
  'weekday in a given month. Memorial Day is the LAST Monday of May, which the '
  'Nth-weekday helper cannot express. dow follows extract(dow from date). Pure '
  'computation, IMMUTABLE.';

-- ---------------------------------------------------------------------------
-- Backfill for tenants predating this migration
--
-- A ONE-TIME BOOTSTRAP -- the 018/019 precedent -- not the ongoing
-- platform-to-tenant propagation 17.A.3 forbids. Without it, existing tenants
-- hold zero rows and their business-day math silently skips weekends only.
--
-- Idempotent via where-not-exists (018/019's guard), NOT 011's on-conflict:
-- there is no unique index to serve as an arbiter, and adding one would
-- contradict the locked sketch.
--
-- 2026-2036 is the STARTING HORIZON, extended thereafter by the rolling top-up
-- once pg_cron lands. See the header: until that job exists, this range is the
-- horizon in fact.
-- ---------------------------------------------------------------------------
insert into public.tenant_holidays (tenant_id, holiday_date, label)
select t.id, h.holiday_date, h.label
from public.tenants t
cross join generate_series(2026, 2036) as y(year)
cross join lateral public.federal_holidays_for_year(y.year) as h
where not exists (
  select 1 from public.tenant_holidays x
  where x.tenant_id = t.id
    and x.holiday_date = h.holiday_date
    and x.label = h.label
);

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.tenant_holidays enable row level security;

create policy "tenant_holidays: tenant read"
  on public.tenant_holidays
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: seeding at provisioning, tenant edits through
-- the calendar admin UI, and the rolling top-up all run through Server Actions.

grant all on public.tenant_holidays to anon, authenticated, service_role;
