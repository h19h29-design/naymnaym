create extension if not exists pgcrypto;

create table if not exists public.nyam_parent_links (
    child_link_id uuid primary key,
    invite_code text not null unique,
    invite_secret_hash text not null,
    child_nickname text not null,
    school_name text not null,
    office_code text not null,
    school_code text not null,
    region_name text not null default '',
    mode text not null,
    share_eating_records boolean not null default true,
    share_challenge_records boolean not null default true,
    share_allergy_warnings boolean not null default true,
    share_photos boolean not null default false,
    created_at timestamptz not null default now(),
    registered_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint nyam_parent_links_invite_code_format
        check (invite_code ~ '^NYAM-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$'),
    constraint nyam_parent_links_mode_check
        check (mode in ('elementary', 'middle', 'high', 'parent'))
);

create table if not exists public.nyam_parent_meal_records (
    child_link_id uuid not null references public.nyam_parent_links(child_link_id) on delete cascade,
    record_id uuid not null,
    meal_date text not null,
    menu_name text not null,
    eating_status text not null,
    difficulty_reasons text[] not null default '{}',
    allergy_codes integer[] not null default '{}',
    photo_ids text[] not null default '{}',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (child_link_id, record_id),
    constraint nyam_parent_meal_records_status_check
        check (eating_status in ('finished', 'half', 'oneBite', 'smelledOnly', 'difficultToday', 'allergyAvoided'))
);

create table if not exists public.nyam_parent_challenge_records (
    child_link_id uuid not null references public.nyam_parent_links(child_link_id) on delete cascade,
    record_id uuid not null,
    challenge_date text not null,
    menu_name text not null,
    action text not null,
    gained_exp integer not null default 0,
    badge_name text,
    nutrients text[] not null default '{}',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (child_link_id, record_id),
    constraint nyam_parent_challenge_records_action_check
        check (action in ('skipped', 'oneBite', 'alreadyEats'))
);

create index if not exists nyam_parent_links_invite_code_idx
    on public.nyam_parent_links(invite_code);

create index if not exists nyam_parent_meal_records_child_date_idx
    on public.nyam_parent_meal_records(child_link_id, meal_date desc, created_at desc);

create index if not exists nyam_parent_challenge_records_child_date_idx
    on public.nyam_parent_challenge_records(child_link_id, challenge_date desc, created_at desc);

alter table public.nyam_parent_links enable row level security;
alter table public.nyam_parent_meal_records enable row level security;
alter table public.nyam_parent_challenge_records enable row level security;

revoke all on public.nyam_parent_links from anon, authenticated;
revoke all on public.nyam_parent_meal_records from anon, authenticated;
revoke all on public.nyam_parent_challenge_records from anon, authenticated;
