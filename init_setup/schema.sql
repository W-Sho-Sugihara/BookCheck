CREATE SEQUENCE card_number_seq START WITH 100000 MAXVALUE 999999;

CREATE TABLE users (
  id int PRIMARY KEY DEFAULT nextval('card_number_seq'),
  first_name text NOT NULL,
  last_name text NOT NULL,
  password text NOT NULL,
  admin boolean DEFAULT false,
  UNIQUE(first_name, last_name, password)
);

CREATE TABLE books (
  id serial PRIMARY KEY,
  title text NOT NULL,
  author text NOT NULL,
  checked_out boolean NOT NULL DEFAULT false,
  checked_out_user_id int REFERENCES users(id) DEFAULT NULL,
  date_checked_out date
);

-- CREATE TABLE book_check_out_history (
--   id serial PRIMARY KEY,
--   user_id int NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   book_id int NOT NULL REFERENCES books(id) ON DELETE CASCADE,
--   date_checked_out date NOT NULL,
--   date_returned date
-- );

