alter table public.nyam_parent_links
    add column if not exists connected_at timestamptz;
