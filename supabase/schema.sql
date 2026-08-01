-- =============================================================================
-- MyBudga — Supabase PostgreSQL Schema
-- YNAB4-style envelope budgeting with household sharing
-- =============================================================================
-- Run this entire script in the Supabase SQL editor.
-- Assumes the auth schema (auth.users) is already present (standard Supabase).
-- =============================================================================


-- =============================================================================
-- SECTION 1: EXTENSIONS
-- =============================================================================

create extension if not exists "uuid-ossp";


-- =============================================================================
-- SECTION 2: CUSTOM TYPES / ENUMS
-- =============================================================================

create type household_role         as enum ('owner', 'member');
create type account_type           as enum ('checking', 'savings', 'credit_card', 'line_of_credit', 'cash', 'investment', 'mortgage', 'loan', 'asset');
create type pay_frequency          as enum ('weekly', 'biweekly', 'monthly');
create type rollover_behavior      as enum ('rollover', 'zero_out');
create type overspending_behavior  as enum ('reduce_tbb', 'carry_forward');
create type transaction_status     as enum ('pending_review', 'confirmed');
create type scheduled_frequency    as enum ('once', 'weekly', 'biweekly', 'monthly', 'yearly');
create type goal_type              as enum ('target_by_date', 'monthly_savings', 'monthly_spending');


-- =============================================================================
-- SECTION 3: HOUSEHOLDS & MEMBERSHIP
-- =============================================================================

create table households (
    id                       uuid primary key default gen_random_uuid(),
    name                     text not null,
    default_currency         char(3) not null default 'USD',
    pay_frequency            pay_frequency not null default 'monthly',
    pay_period_anchor_date   date,
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now()
);

create table household_members (
    id            uuid primary key default gen_random_uuid(),
    household_id  uuid not null references households(id) on delete cascade,
    user_id       uuid not null references auth.users(id) on delete cascade,
    role          household_role not null default 'member',
    invited_by    uuid references auth.users(id),
    joined_at     timestamptz not null default now(),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    unique (household_id, user_id)
);

create index idx_household_members_household on household_members(household_id);
create index idx_household_members_user      on household_members(user_id);


-- =============================================================================
-- SECTION 4: ACCOUNTS
-- =============================================================================

create table accounts (
    id                      uuid primary key default gen_random_uuid(),
    household_id            uuid not null references households(id) on delete cascade,
    name                    text not null,
    nickname                text,
    account_type            account_type not null,
    is_tracking             boolean not null default false,
    last_four               char(4),
    starting_balance        numeric(12,2) not null default 0,
    current_balance         numeric(12,2) not null default 0,
    is_active               boolean not null default true,
    cc_payment_category_id  uuid,  -- FK added after categories table
    start_date              date,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

create index idx_accounts_household on accounts(household_id);
create index idx_accounts_type      on accounts(account_type);
create index idx_accounts_active    on accounts(household_id, is_active);


-- =============================================================================
-- SECTION 5: CATEGORY GROUPS & CATEGORIES
-- =============================================================================

create table category_groups (
    id            uuid primary key default gen_random_uuid(),
    household_id  uuid not null references households(id) on delete cascade,
    name          text not null,
    sort_order    integer not null default 0,
    is_hidden     boolean not null default false,
    deleted_at    timestamptz,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_category_groups_household on category_groups(household_id);

create table categories (
    id                    uuid primary key default gen_random_uuid(),
    household_id          uuid not null references households(id) on delete cascade,
    category_group_id     uuid not null references category_groups(id) on delete cascade,
    name                  text not null,
    sort_order            integer not null default 0,
    is_hidden             boolean not null default false,
    -- First month the category no longer applies. Null = active. Dated rather
    -- than a second flag so past months keep showing it: a trip that ran in
    -- July must still appear in July's budget after it is retired in August.
    inactive_from         date,
    rollover_behavior     rollover_behavior not null default 'rollover',
    overspending_behavior overspending_behavior not null default 'reduce_tbb',
    is_cc_payment         boolean not null default false,
    linked_account_id     uuid references accounts(id) on delete set null,
    deleted_at            timestamptz,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now()
);

create index idx_categories_household       on categories(household_id);
create index idx_categories_group           on categories(category_group_id);
create index idx_categories_linked_account  on categories(linked_account_id);
create index idx_categories_inactive_from   on categories(inactive_from);

-- Deferred FK: accounts → cc_payment_category_id
alter table accounts
    add constraint fk_accounts_cc_payment_category
    foreign key (cc_payment_category_id) references categories(id) on delete set null;


-- =============================================================================
-- SECTION 6: CATEGORY GOALS
-- =============================================================================

create table category_goals (
    id             uuid primary key default gen_random_uuid(),
    household_id   uuid not null references households(id) on delete cascade,
    category_id    uuid not null references categories(id) on delete cascade,
    goal_type      goal_type not null default 'target_by_date',
    target_amount  numeric(12,2) not null,
    target_date    date,           -- required for target_by_date
    monthly_amount numeric(12,2),  -- required for monthly_savings / monthly_spending
    is_active      boolean not null default true,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    unique (category_id)           -- one active goal per category
);

create index idx_category_goals_household on category_goals(household_id);
create index idx_category_goals_category  on category_goals(category_id);


-- =============================================================================
-- SECTION 7: BUDGET MONTHS
-- =============================================================================

create table budget_months (
    id            uuid primary key default gen_random_uuid(),
    household_id  uuid not null references households(id) on delete cascade,
    category_id   uuid not null references categories(id) on delete cascade,
    month         date not null check (extract(day from month) = 1),
    budgeted      numeric(12,2) not null default 0,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    unique (household_id, category_id, month)
);

create index idx_budget_months_household on budget_months(household_id);
create index idx_budget_months_category  on budget_months(category_id);
create index idx_budget_months_month     on budget_months(household_id, month);


-- =============================================================================
-- SECTION 8: PAYEES
-- =============================================================================

create table payees (
    id                   uuid primary key default gen_random_uuid(),
    household_id         uuid not null references households(id) on delete cascade,
    name                 text not null,
    default_category_id  uuid references categories(id) on delete set null,
    deleted_at           timestamptz,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);

create index idx_payees_household on payees(household_id);
create index idx_payees_name      on payees(household_id, name);

create unique index idx_payees_unique_name
    on payees(household_id, lower(name))
    where deleted_at is null;


-- =============================================================================
-- SECTION 9: TRANSACTIONS
-- =============================================================================

create table transactions (
    id            uuid primary key default gen_random_uuid(),
    household_id  uuid not null references households(id) on delete cascade,
    account_id    uuid not null references accounts(id) on delete cascade,
    payee_id      uuid references payees(id) on delete set null,
    category_id   uuid references categories(id) on delete set null,
    amount        numeric(12,2) not null,
    date          date not null,
    memo          text,
    cleared       boolean not null default false,
    reconciled    boolean not null default false,
    status        transaction_status not null default 'confirmed',
    transfer_id   uuid references transactions(id) on delete set null,
    is_split      boolean not null default false,
    deleted_at    timestamptz,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_transactions_household on transactions(household_id);
create index idx_transactions_account   on transactions(account_id);
create index idx_transactions_category  on transactions(category_id);
create index idx_transactions_payee     on transactions(payee_id);
create index idx_transactions_date      on transactions(household_id, date);
create index idx_transactions_transfer  on transactions(transfer_id);
create index idx_transactions_status    on transactions(status) where deleted_at is null;


-- =============================================================================
-- SECTION 10: SPLIT TRANSACTIONS
-- =============================================================================

create table split_transactions (
    id                     uuid primary key default gen_random_uuid(),
    household_id           uuid not null references households(id) on delete cascade,
    parent_transaction_id  uuid not null references transactions(id) on delete cascade,
    category_id            uuid references categories(id) on delete set null,
    amount                 numeric(12,2) not null,
    memo                   text,
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now()
);

create index idx_split_transactions_parent    on split_transactions(parent_transaction_id);
create index idx_split_transactions_category  on split_transactions(category_id);
create index idx_split_transactions_household on split_transactions(household_id);


-- =============================================================================
-- SECTION 11: SCHEDULED TRANSACTIONS
-- =============================================================================

create table scheduled_transactions (
    id            uuid primary key default gen_random_uuid(),
    household_id  uuid not null references households(id) on delete cascade,
    account_id    uuid not null references accounts(id) on delete cascade,
    payee_id      uuid references payees(id) on delete set null,
    category_id   uuid references categories(id) on delete set null,
    amount        numeric(12,2) not null,
    memo          text,
    frequency     scheduled_frequency not null,
    next_date     date not null,
    end_date      date,
    auto_approve  boolean not null default false,
    is_active     boolean not null default true,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_scheduled_transactions_household on scheduled_transactions(household_id);
create index idx_scheduled_transactions_account   on scheduled_transactions(account_id);
create index idx_scheduled_transactions_next_date on scheduled_transactions(next_date) where is_active = true;


-- =============================================================================
-- SECTION 12: HELPER — updated_at AUTO-STAMP
-- =============================================================================

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

do $$
declare
    tbl text;
begin
    foreach tbl in array array[
        'households', 'household_members', 'accounts',
        'category_groups', 'categories', 'category_goals',
        'budget_months', 'payees', 'transactions',
        'split_transactions', 'scheduled_transactions'
    ] loop
        execute format(
            'create trigger trg_%s_updated_at
             before update on %I
             for each row execute function set_updated_at();',
            tbl, tbl
        );
    end loop;
end;
$$;


-- =============================================================================
-- SECTION 13: TRIGGER — AUTO-CREATE CC PAYMENT CATEGORY ON ACCOUNT INSERT
-- =============================================================================

create or replace function create_cc_payment_category()
returns trigger language plpgsql security definer as $$
declare
    v_group_id    uuid;
    v_category_id uuid;
begin
    if new.account_type <> 'credit_card' then
        return null;
    end if;

    select id into v_group_id
    from category_groups
    where household_id = new.household_id
      and name = 'Credit Card Payments'
      and deleted_at is null
    limit 1;

    if v_group_id is null then
        insert into category_groups (household_id, name, sort_order)
        values (new.household_id, 'Credit Card Payments', 0)
        returning id into v_group_id;
    end if;

    insert into categories (
        household_id, category_group_id, name,
        is_cc_payment, linked_account_id, sort_order
    )
    values (
        new.household_id, v_group_id,
        coalesce(new.nickname, new.name) || ' Payment',
        true, new.id, 0
    )
    returning id into v_category_id;

    -- AFTER INSERT: account row exists, safe to update cc_payment_category_id
    update accounts
    set cc_payment_category_id = v_category_id
    where id = new.id;

    return null;
end;
$$;

drop trigger if exists trg_accounts_cc_payment on accounts;

create trigger trg_accounts_cc_payment
    after insert on accounts
    for each row execute function create_cc_payment_category();


-- =============================================================================
-- SECTION 14: TRIGGER — CC SPENDING → AUTO-FUND CC PAYMENT CATEGORY
-- =============================================================================

create or replace function handle_cc_spending()
returns trigger language plpgsql security definer as $$
declare
    v_account   accounts%rowtype;
    v_category  categories%rowtype;
    v_cc_cat_id uuid;
    v_month     date;
begin
    if TG_OP <> 'INSERT' then
        return new;
    end if;

    if new.deleted_at is not null or new.category_id is null then
        return new;
    end if;

    select * into v_account from accounts where id = new.account_id;
    if v_account.account_type <> 'credit_card' then
        return new;
    end if;

    select * into v_category from categories where id = new.category_id;
    if v_category.is_cc_payment then
        return new;
    end if;

    v_cc_cat_id := v_account.cc_payment_category_id;
    if v_cc_cat_id is null then
        return new;
    end if;

    v_month := date_trunc('month', new.date)::date;

    insert into budget_months (household_id, category_id, month, budgeted)
    values (new.household_id, v_cc_cat_id, v_month, -new.amount)
    on conflict (household_id, category_id, month)
    do update set
        budgeted   = budget_months.budgeted + excluded.budgeted,
        updated_at = now();

    return new;
end;
$$;

create trigger trg_transactions_cc_spending
    after insert on transactions
    for each row execute function handle_cc_spending();


-- =============================================================================
-- SECTION 15: TRIGGER — MAINTAIN account.current_balance
-- =============================================================================

create or replace function update_account_balance()
returns trigger language plpgsql security definer as $$
begin
    if TG_OP = 'INSERT' and new.deleted_at is null then
        update accounts set current_balance = current_balance + new.amount
        where id = new.account_id;

    elsif TG_OP = 'UPDATE' then
        if old.deleted_at is not null and new.deleted_at is null then
            update accounts set current_balance = current_balance + new.amount
            where id = new.account_id;
        elsif old.deleted_at is null and new.deleted_at is not null then
            update accounts set current_balance = current_balance - old.amount
            where id = old.account_id;
        elsif old.deleted_at is null and new.deleted_at is null then
            update accounts set current_balance = current_balance - old.amount
            where id = old.account_id;
            update accounts set current_balance = current_balance + new.amount
            where id = new.account_id;
        end if;

    elsif TG_OP = 'DELETE' then
        if old.deleted_at is null then
            update accounts set current_balance = current_balance - old.amount
            where id = old.account_id;
        end if;
    end if;

    return coalesce(new, old);
end;
$$;

create trigger trg_transactions_balance
    after insert or update or delete on transactions
    for each row execute function update_account_balance();


-- =============================================================================
-- SECTION 16: VIEW — BUDGET MONTH SUMMARY (activity + rolling balance)
-- =============================================================================

create or replace view v_budget_month_summary as
with recursive monthly_balance as (
    -- Base: earliest month per category
    select
        bm.id,
        bm.household_id,
        bm.category_id,
        bm.month,
        bm.budgeted,
        coalesce((
            select sum(t.amount)
            from transactions t
            where t.category_id  = bm.category_id
              and t.household_id = bm.household_id
              and date_trunc('month', t.date)::date = bm.month
              and t.deleted_at is null
        ), 0)::numeric(12,2) as activity,
        0::numeric(12,2) as carried_balance
    from budget_months bm
    where bm.month = (
        select min(b2.month) from budget_months b2 where b2.category_id = bm.category_id
    )

    union all

    select
        bm.id,
        bm.household_id,
        bm.category_id,
        bm.month,
        bm.budgeted,
        coalesce((
            select sum(t.amount)
            from transactions t
            where t.category_id  = bm.category_id
              and t.household_id = bm.household_id
              and date_trunc('month', t.date)::date = bm.month
              and t.deleted_at is null
        ), 0)::numeric(12,2) as activity,
        cast(
            case c.rollover_behavior
                when 'rollover' then
                    greatest(
                        monthly_balance.carried_balance + monthly_balance.budgeted + monthly_balance.activity,
                        case c.overspending_behavior
                            when 'reduce_tbb' then 0::numeric(12,2)
                            else monthly_balance.carried_balance + monthly_balance.budgeted + monthly_balance.activity
                        end
                    )
                when 'zero_out' then 0::numeric(12,2)
            end
        as numeric(12,2)) as carried_balance
    from budget_months bm
    join monthly_balance on (
        monthly_balance.category_id = bm.category_id
        and monthly_balance.month = (bm.month - interval '1 month')::date
    )
    join categories c on c.id = bm.category_id
)
select
    mb.id,
    mb.household_id,
    mb.category_id,
    mb.month,
    mb.budgeted,
    mb.activity,
    mb.carried_balance,
    mb.carried_balance + mb.budgeted + mb.activity as balance
from monthly_balance mb;


-- =============================================================================
-- SECTION 17: VIEW — TO BE BUDGETED (TBB) PER HOUSEHOLD PER MONTH
-- =============================================================================

create or replace view v_to_be_budgeted as
select
    hm_month.household_id,
    hm_month.month,
    coalesce(inflows.total_inflows, 0)   as total_inflows,
    coalesce(budgeted.total_budgeted, 0) as total_budgeted,
    coalesce(inflows.total_inflows, 0) - coalesce(budgeted.total_budgeted, 0) as to_be_budgeted
from (
    select distinct household_id, month from budget_months
) hm_month
left join lateral (
    select sum(t.amount) as total_inflows
    from transactions t
    join accounts a on a.id = t.account_id
    where t.household_id = hm_month.household_id
      and date_trunc('month', t.date)::date = hm_month.month
      and t.amount > 0
      and t.deleted_at is null
      and a.is_tracking = false
) inflows on true
left join lateral (
    select sum(budgeted) as total_budgeted
    from budget_months
    where household_id = hm_month.household_id
      and month = hm_month.month
) budgeted on true;


-- =============================================================================
-- SECTION 18: ROW-LEVEL SECURITY (RLS)
-- =============================================================================

alter table households             enable row level security;
alter table household_members      enable row level security;
alter table accounts               enable row level security;
alter table category_groups        enable row level security;
alter table categories             enable row level security;
alter table category_goals         enable row level security;
alter table budget_months          enable row level security;
alter table payees                 enable row level security;
alter table transactions           enable row level security;
alter table split_transactions     enable row level security;
alter table scheduled_transactions enable row level security;

-- households
create policy "members can view their household"
    on households for select
    using (id in (select household_id from household_members where user_id = auth.uid()));

create policy "owner can update household settings"
    on households for update
    using (id in (select household_id from household_members where user_id = auth.uid() and role = 'owner'));

-- household_members
create policy "members can view household membership"
    on household_members for select
    using (user_id = auth.uid());

create policy "owners can insert new members"
    on household_members for insert
    with check (household_id in (select household_id from household_members where user_id = auth.uid() and role = 'owner'));

create policy "owners can remove members"
    on household_members for delete
    using (household_id in (select household_id from household_members where user_id = auth.uid() and role = 'owner'));

create policy "members can remove themselves"
    on household_members for delete
    using (user_id = auth.uid());

-- accounts
create policy "household members can view accounts"
    on accounts for select
    using (household_id in (select household_id from household_members where user_id = auth.uid()));
create policy "household members can insert accounts"
    on accounts for insert
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));
create policy "household members can update accounts"
    on accounts for update
    using (household_id in (select household_id from household_members where user_id = auth.uid()));
create policy "household members can delete accounts"
    on accounts for delete
    using (household_id in (select household_id from household_members where user_id = auth.uid()));

-- category_groups
create policy "household members can manage category_groups"
    on category_groups for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- categories
create policy "household members can manage categories"
    on categories for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- category_goals
create policy "household members can manage category_goals"
    on category_goals for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- budget_months
create policy "household members can manage budget_months"
    on budget_months for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- payees
create policy "household members can manage payees"
    on payees for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- transactions
create policy "household members can manage transactions"
    on transactions for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- split_transactions
create policy "household members can manage split_transactions"
    on split_transactions for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));

-- scheduled_transactions
create policy "household members can manage scheduled_transactions"
    on scheduled_transactions for all
    using (household_id in (select household_id from household_members where user_id = auth.uid()))
    with check (household_id in (select household_id from household_members where user_id = auth.uid()));


-- =============================================================================
-- SECTION 19: FUNCTION — PROCESS DUE SCHEDULED TRANSACTIONS (via pg_cron)
-- =============================================================================
-- Enable pg_cron in Supabase dashboard → Extensions, then schedule:
--   select cron.schedule('process-scheduled-txns', '0 6 * * *',
--     $$select process_due_scheduled_transactions();$$);

create or replace function process_due_scheduled_transactions()
returns void language plpgsql security definer as $$
declare
    rec          scheduled_transactions%rowtype;
    v_next_date  date;
    v_is_active  boolean;
begin
    for rec in
        select * from scheduled_transactions
        where is_active = true and next_date <= current_date
    loop
        insert into transactions (
            household_id, account_id, payee_id, category_id,
            amount, date, memo, status
        ) values (
            rec.household_id, rec.account_id, rec.payee_id, rec.category_id,
            rec.amount, rec.next_date, rec.memo,
            case when rec.auto_approve
                 then 'confirmed'::transaction_status
                 else 'pending_review'::transaction_status
            end
        );

        -- Compute next_date (keep current value for 'once' — it will be deactivated)
        v_next_date := case rec.frequency
            when 'once'      then rec.next_date  -- irrelevant; record deactivated below
            when 'weekly'    then rec.next_date + interval '7 days'
            when 'biweekly'  then rec.next_date + interval '14 days'
            when 'monthly'   then (rec.next_date + interval '1 month')::date
            when 'yearly'    then (rec.next_date + interval '1 year')::date
        end;

        -- Deactivate if 'once' or past end_date
        v_is_active := case
            when rec.frequency = 'once' then false
            when rec.end_date is not null and v_next_date > rec.end_date then false
            else true
        end;

        update scheduled_transactions
        set next_date = v_next_date, is_active = v_is_active
        where id = rec.id;
    end loop;
end;
$$;


-- =============================================================================
-- SECTION 20: FUNCTION — BOOTSTRAP A NEW HOUSEHOLD
-- =============================================================================
-- Called from the Flutter app after first sign-up.
-- Creates household, adds owner, seeds default YNAB-style category groups/categories.
-- Returns the new household_id so the client can cache it.

create or replace function bootstrap_household(
    p_user_id        uuid,
    p_household_name text default 'Our Budget'
)
returns uuid language plpgsql security definer as $$
declare
    v_household_id uuid;
    v_group_id     uuid;
begin
    -- Create the household
    insert into households (name)
    values (p_household_name)
    returning id into v_household_id;

    -- Add the user as owner
    insert into household_members (household_id, user_id, role)
    values (v_household_id, p_user_id, 'owner');

    -- Seed YNAB4-style category groups
    insert into category_groups (household_id, name, sort_order) values
        (v_household_id, 'Immediate Obligations', 10),
        (v_household_id, 'True Expenses',         20),
        (v_household_id, 'Debt Payments',         30),
        (v_household_id, 'Quality of Life Goals', 40),
        (v_household_id, 'Just for Fun',          50);

    -- Seed starter categories under Immediate Obligations
    select id into v_group_id
    from category_groups
    where household_id = v_household_id and name = 'Immediate Obligations';

    insert into categories (household_id, category_group_id, name, sort_order) values
        (v_household_id, v_group_id, 'Rent / Mortgage', 10),
        (v_household_id, v_group_id, 'Groceries',       20),
        (v_household_id, v_group_id, 'Utilities',       30),
        (v_household_id, v_group_id, 'Transportation',  40),
        (v_household_id, v_group_id, 'Phone',           50);

    return v_household_id;
end;
$$;


-- =============================================================================
-- SECTION 21: GRANT PERMISSIONS
-- =============================================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete on
    households,
    household_members,
    accounts,
    category_groups,
    categories,
    category_goals,
    budget_months,
    payees,
    transactions,
    split_transactions,
    scheduled_transactions
to authenticated;

grant select on v_budget_month_summary, v_to_be_budgeted to authenticated;

grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on function process_due_scheduled_transactions() to service_role;
grant execute on function bootstrap_household(uuid, text)     to authenticated;
grant execute on function bootstrap_household(uuid, text)     to service_role;
