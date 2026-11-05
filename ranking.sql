begin;

create table if not exists public.hanja_best (
  nickname text primary key check (nickname ~ '^[0-9]{4}$'),
  correct integer not null check (correct between 0 and 30),
  tenths integer not null check (tenths > 0)
);
alter table public.hanja_best enable row level security;
revoke all on public.hanja_best from public, anon, authenticated;

create table if not exists public.hanja_monthly_best (
  month_start date not null,
  nickname text not null check (nickname ~ '^[0-9]{4}$'),
  correct integer not null check (correct between 0 and 30),
  tenths integer not null check (tenths > 0),
  primary key (month_start, nickname)
);
alter table public.hanja_monthly_best enable row level security;
revoke all on public.hanja_monthly_best from public, anon, authenticated;

lock table public.hanja_best in access exclusive mode;
insert into public.hanja_monthly_best
select date '2026-11-01', nickname, correct, tenths from public.hanja_best
on conflict do nothing;

create or replace function public.hanja_submit(p_nickname text, p_correct integer, p_tenths integer)
returns void language sql security definer set search_path = '' as $$
  insert into public.hanja_monthly_best as best (month_start, nickname, correct, tenths)
  values (date_trunc('month', statement_timestamp() at time zone 'Asia/Seoul')::date, p_nickname, p_correct, p_tenths)
  on conflict (month_start, nickname) do update
  set correct = excluded.correct, tenths = excluded.tenths
  where excluded.correct > best.correct
     or (excluded.correct = best.correct and excluded.tenths < best.tenths);
$$;

create or replace function public.hanja_board(p_nickname text default null)
returns table(place bigint, nickname text, correct integer, tenths integer)
language sql stable security definer set search_path = '' as $$
  select * from (
    select rank() over (order by b.correct desc, b.tenths) as place,
           b.nickname, b.correct, b.tenths from public.hanja_monthly_best b
    where b.month_start = date_trunc('month', statement_timestamp() at time zone 'Asia/Seoul')::date
  ) ranked
  where ranked.place <= 10 or ranked.nickname = p_nickname
  order by ranked.place, ranked.nickname;
$$;
revoke all on function public.hanja_submit(text, integer, integer), public.hanja_board(text) from public;
grant execute on function public.hanja_submit(text, integer, integer), public.hanja_board(text) to anon, authenticated;
commit;
