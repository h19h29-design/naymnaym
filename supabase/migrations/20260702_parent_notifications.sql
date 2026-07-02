alter table public.nyam_parent_links
    add column if not exists last_notification_signature text,
    add column if not exists last_notification_at timestamptz;

alter table public.nyam_parent_links
    alter column share_photos set default false;

update public.nyam_parent_links
set share_photos = false
where share_photos is true;

update public.nyam_parent_meal_records
set photo_ids = '{}'
where photo_ids <> '{}';

create table if not exists public.nyam_parent_devices (
    id uuid primary key default gen_random_uuid(),
    child_link_id uuid not null references public.nyam_parent_links(child_link_id) on delete cascade,
    device_token_hash text not null,
    device_token text not null,
    environment text not null,
    platform text not null default 'ios',
    is_active boolean not null default true,
    last_registered_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint nyam_parent_devices_environment_check
        check (environment in ('sandbox', 'production')),
    constraint nyam_parent_devices_platform_check
        check (platform in ('ios'))
);

create unique index if not exists nyam_parent_devices_child_token_idx
    on public.nyam_parent_devices(child_link_id, device_token_hash);

create index if not exists nyam_parent_devices_child_active_idx
    on public.nyam_parent_devices(child_link_id, is_active);

alter table public.nyam_parent_devices enable row level security;

revoke all on public.nyam_parent_devices from anon, authenticated;
