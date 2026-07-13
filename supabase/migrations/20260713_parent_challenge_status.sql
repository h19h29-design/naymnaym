alter table public.nyam_parent_challenge_records
    add column if not exists eating_status text;

alter table public.nyam_parent_challenge_records
    drop constraint if exists nyam_parent_challenge_records_eating_status_check;

alter table public.nyam_parent_challenge_records
    add constraint nyam_parent_challenge_records_eating_status_check
    check (
        eating_status is null
        or eating_status in (
            'finished',
            'half',
            'oneBite',
            'smelledOnly',
            'difficultToday',
            'allergyAvoided'
        )
    );
