-- Steam discount panel: database schema (PostgreSQL / Neon)

CREATE TABLE IF NOT EXISTS games (
  appid               integer PRIMARY KEY,
  name                text,
  developer           text,
  publisher           text,
  initial_price_cents integer,
  positive            integer,
  negative            integer,
  owners_band         text,
  ccu_at_selection    integer,
  stratum             integer,
  selected_at         timestamptz NOT NULL DEFAULT now(),
  active              boolean     NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS player_counts (
  appid        integer     NOT NULL REFERENCES games(appid),
  ts           timestamptz NOT NULL,
  player_count integer     NOT NULL,
  PRIMARY KEY (appid, ts)
);

CREATE TABLE IF NOT EXISTS prices (
  appid         integer     NOT NULL REFERENCES games(appid),
  ts            timestamptz NOT NULL,
  has_price     boolean     NOT NULL,
  currency      text,
  initial_cents integer,
  final_cents   integer,
  discount_pct  integer,
  PRIMARY KEY (appid, ts)
);

CREATE TABLE IF NOT EXISTS runs (
  run_id      bigserial   PRIMARY KEY,
  job         text        NOT NULL,
  started_at  timestamptz NOT NULL,
  finished_at timestamptz,
  n_ok        integer,
  n_fail      integer,
  note        text
);

-- Release date per game (filled once by R/fetch_release_dates.R)
ALTER TABLE games ADD COLUMN IF NOT EXISTS release_date date;
ALTER TABLE games ADD COLUMN IF NOT EXISTS release_date_raw text;

CREATE TABLE IF NOT EXISTS reviews (
  appid          integer     NOT NULL REFERENCES games(appid),
  ts             timestamptz NOT NULL,
  total_positive integer,
  total_negative integer,
  total_reviews  integer,
  PRIMARY KEY (appid, ts)
);
