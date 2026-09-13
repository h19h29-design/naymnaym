create table if not exists public.nyam_ai_daily_usage (
  subject_hash text not null check (subject_hash ~ '^[0-9a-f]{64}$'),
  usage_day date not null,
  attempts smallint not null default 0 check (attempts between 0 and 3),
  success_request_hash text check (success_request_hash is null or success_request_hash ~ '^[0-9a-f]{64}$'),
  pending_request_hash text check (pending_request_hash is null or pending_request_hash ~ '^[0-9a-f]{64}$'),
  pending_fingerprint text check (pending_fingerprint is null or pending_fingerprint ~ '^[0-9a-f]{64}$'),
  lease_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (subject_hash, usage_day)
);

create table if not exists public.nyam_ai_daily_global_usage (
  usage_day date primary key,
  attempts integer not null default 0 check (attempts between 0 and 100),
  updated_at timestamptz not null default now()
);

alter table public.nyam_ai_daily_usage enable row level security;
alter table public.nyam_ai_daily_global_usage enable row level security;

revoke all on table public.nyam_ai_daily_usage from public, anon, authenticated;
revoke all on table public.nyam_ai_daily_global_usage from public, anon, authenticated;
grant select, insert, update on table public.nyam_ai_daily_usage to service_role;
grant select, insert, update on table public.nyam_ai_daily_global_usage to service_role;

create or replace function public.nyam_ai_claim_daily(
  p_subject_hash text,
  p_day date,
  p_request_hash text,
  p_fingerprint text
) returns text
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  current_usage public.nyam_ai_daily_usage%rowtype;
  global_attempts integer;
begin
  if p_subject_hash !~ '^[0-9a-f]{64}$'
     or p_request_hash !~ '^[0-9a-f]{64}$'
     or p_fingerprint !~ '^[0-9a-f]{64}$' then
    return 'storage_unavailable';
  end if;

  insert into public.nyam_ai_daily_usage (subject_hash, usage_day)
  values (p_subject_hash, p_day)
  on conflict do nothing;

  select * into current_usage
  from public.nyam_ai_daily_usage
  where subject_hash = p_subject_hash and usage_day = p_day
  for update;

  if current_usage.success_request_hash is not null then
    return 'daily_used';
  end if;
  if current_usage.pending_request_hash is not null then
    if current_usage.lease_until > now() then
      return 'in_progress';
    end if;
    return 'recovery_unavailable';
  end if;
  if current_usage.attempts >= 3 then
    return 'daily_attempt_limit';
  end if;

  insert into public.nyam_ai_daily_global_usage (usage_day)
  values (p_day)
  on conflict do nothing;

  select attempts into global_attempts
  from public.nyam_ai_daily_global_usage
  where usage_day = p_day
  for update;

  if global_attempts >= 100 then
    return 'global_limit';
  end if;

  update public.nyam_ai_daily_usage
  set attempts = attempts + 1,
      pending_request_hash = p_request_hash,
      pending_fingerprint = p_fingerprint,
      lease_until = now() + interval '20 seconds',
      updated_at = now()
  where subject_hash = p_subject_hash and usage_day = p_day;

  update public.nyam_ai_daily_global_usage
  set attempts = attempts + 1, updated_at = now()
  where usage_day = p_day;

  return 'claimed';
end;
$$;

create or replace function public.nyam_ai_finish_daily(
  p_subject_hash text,
  p_day date,
  p_request_hash text,
  p_success boolean
) returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  update public.nyam_ai_daily_usage
  set success_request_hash = case when p_success then p_request_hash else success_request_hash end,
      pending_request_hash = null,
      pending_fingerprint = null,
      lease_until = null,
      updated_at = now()
  where subject_hash = p_subject_hash
    and usage_day = p_day
    and pending_request_hash = p_request_hash;
end;
$$;

revoke all on function public.nyam_ai_claim_daily(text, date, text, text) from public, anon, authenticated;
revoke all on function public.nyam_ai_finish_daily(text, date, text, boolean) from public, anon, authenticated;
grant execute on function public.nyam_ai_claim_daily(text, date, text, text) to service_role;
grant execute on function public.nyam_ai_finish_daily(text, date, text, boolean) to service_role;
