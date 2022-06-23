require 'yaml'
require 'pg'
require 'bcrypt'

DB = PG.connect(dbname: "library")

#  helper methods

def query(sql, *params)
  DB.exec_params(sql, params)
end

def encrypt_password(password)
  BCrypt::Password.create(password)
end

def generate_random_date(days_back) # a random date upto 5 years ago is 1825 days back
  (DateTime.now - (rand * days_back)).to_date
end

# populate DB methods

def populate_books_table
  books = YAML.load(File.read("init_setup/books.yml"))["books"]
  books.each do |title, author|
    sql = "INSERT INTO books (title, author) VALUES ($1, $2);"
    query(sql, title, author)
  end
end

populate_books_table()

def populate_users_table
  users = [
    {first_name: 'Sho', last_name: 'Sugihara', password: encrypt_password("shos_assessment"), admin: true},
    {first_name: 'Joseph', last_name: 'Smith', password: encrypt_password("test_user_1"), admin: false},
    {first_name: 'Russel M', last_name: 'Nelson', password: encrypt_password("test_user_2"), admin: false},
  ]
  
  users.each do |user|
    sql = <<~SQL
      INSERT INTO users(first_name, last_name, password, admin)
      VALUES($1, $2, $3, $4);
    SQL
  
    query(sql, user[:first_name], user[:last_name], user[:password], user[:admin])
  end
end

populate_users_table()

# def insert_random_book_checkout_history(user_id, book_count_start, book_start_end) 
#   #book count 1~100
#   (book_count_start..book_start_end).each do |book_id|
#     sql = <<~SQL
#       INSERT INTO book_check_out_history(book_id, user_id, date_checked_out, date_returned)
#       VALUES($1, $2, $3, $4);
#     SQL
#     random_date = generate_random_date(1825) # a random date upto 5 years ago is 1825 days back
#     date_checked_out = random_date.to_s
#     date_returned = generate_random_return_date(random_date)
#     query(sql, book_id, user_id, date_checked_out,date_returned)
#   end
# end

# insert_random_book_checkout_history(100000, 1, 25)
# insert_random_book_checkout_history(100001, 50, 80)

def init_books_currently_checked_out(user_id, book_id)
  sql_update_books = <<~SQL
  UPDATE books SET checked_out = true, checked_out_user_id = $1, date_checked_out = $2 WHERE id = $3;
  SQL
  # sql = <<~SQL
  #   INSERT INTO book_check_out_history(user_id, book_id, date_checked_out)
  #   VALUES($1, $2, $3);
  # SQL

  query(sql_update_books, user_id, generate_random_date(14), book_id)
end

def random_book_ids(count)
  (1..100).to_a.shuffle[0..count]
end

random_book_ids(14).each do |book_id|
  init_books_currently_checked_out(100000, book_id)
end

random_book_ids(12).each do |book_id|
  init_books_currently_checked_out(100001, book_id)
end
