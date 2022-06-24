require 'pg'
require 'bcrypt'

class DatabasePersistence
  def initialize(logger)
    @db = PG.connect(dbname: 'library')
    @logger = logger
  end

  def query(sql, *params)
    @logger.info "#{sql}: #{params}"
    @db.exec_params(sql, params)
  end

  def disconnect
    @db.close
  end

  # methods used for login validation
  def find_id_num_user(id_num)
    sql = 'SELECT id, password FROM users WHERE id = $1'
    query(sql, id_num).first
  end

  def id_num_matches_password?(id_num, password)
    if find_id_num_user(id_num)
      result = find_id_num_user(id_num)
      BCrypt::Password.new(result['password']) == password
    else
      false
    end
  end

  # finds user based on ID and returns a new User obj
  def find_user(id_number)
    sql = 'SELECT id, first_name, last_name, admin FROM users WHERE id = $1;'
    result = query(sql, id_number).first

    return nil unless !result.nil?

    id = result['id']
    first_name = result['first_name']
    last_name = result['last_name']
    admin = result['admin']

    User.new(id, first_name, last_name, admin)
  end

  # finds book based on ID and returns a new Book obj
  def find_book(book_id)
    sql = <<~SQL
      SELECT * FROM books
      WHERE id = $1;
    SQL

    result = query(sql, book_id).first
    return nil if result.nil?
    data = {
      id: result['id'],
      title: result['title'],
      author: result['author'],
      checked_out: result['checked_out'] == 't',
      checked_out_user_id: result['checked_out_user_id'],
      date_checked_out: result['date_checked_out']
    }

    Book.new(data)
  end

  # adding a new book to DB
  def add_new_book(title, author)
    sql = <<~SQL
      INSERT INTO books (title, author)
      VALUES ($1, $2);
    SQL

    query(sql, title, author)
  end

  # updates book info within DB
  def update_book_info(new_book_info)
    sql = <<~SQL
      UPDATE books SET title = $1, author = $2, checked_out = $3, checked_out_user_id = $4, date_checked_out = $5
      WHERE id = $6
    SQL
    title = new_book_info[:title]
    author = new_book_info[:author]
    checked_out = new_book_info[:checked_out]
    checked_out_user_id = new_book_info[:checked_out_user_id]
    date_checked_out = new_book_info[:date_checked_out]
    book_id = new_book_info[:book_id]

    query(sql, title, author, checked_out, checked_out_user_id, date_checked_out, book_id)
  end

  # deletes book within DB and returns the deleted book title & author for display
  def delete_book(book_id)
    info = query('SELECT title, author FROM books WHERE id = $1', book_id).first.values
    sql = <<~SQL
      DELETE FROM books
      WHERE id = $1
    SQL

    query(sql, book_id)
    info
  end

  # method certifying the new user is a unique user by comparing the names and password.
  def new_user_unique?(first_name, last_name, password)
    sql = <<~SQL
      SELECT * FROM users 
      WHERE first_name LIKE $1 AND last_name LIKE $2;
    SQL
    results = query(sql, first_name, last_name)

    return true if results.first.nil?

    results.all? do |result|
      BCrypt::Password.new(result['password']) != password
    end
  end
  
  def encrypt_password(password)
    BCrypt::Password.create(password)
  end

  # method for adding new user to the DB & returns the new user ID
  def create_new_user(first_name, last_name, password)
    crypt_password = encrypt_password(password)
    sql = <<~SQL
      INSERT INTO users(first_name, last_name, password)
      VALUES($1, $2, $3)
    SQL
    query(sql, first_name, last_name, crypt_password)
    return_new_user_id(first_name, last_name, crypt_password)
  end

  # returns the new ID for the newly created user
  def return_new_user_id(first_name, last_name, crypt_password)
    sql_new_user_id = <<~SQL
      SELECT id FROM users  
      WHERE first_name LIKE $1 AND 
      last_name LIKE $2 AND password LIKE $3;
    SQL
    query(sql_new_user_id, first_name, last_name, crypt_password).values.first.first
  end

  # method for updating user info in DB
  def edit_user_info(id, first_name, last_name)
    sql = <<~SQL
      UPDATE users
        set first_name = $1, last_name = $2
        Where id = $3;
    SQL

    query(sql, first_name.capitalize, last_name.capitalize, id.to_i)
  end

  # deletes user info from the DB
  def delete_user(user_id)
    sql = <<~SQL
      DELETE FROM users WHERE id = $1;
    SQL
    query(sql, user_id)
  end

  # finds the desired books from the DB based on the
  # current list_type within the 'data' hash passed in & returns an array of new Book objs
  def grab_books_from_db(data)
    list_type = data[:list_type]
    @condition = generate_sql_for_grab_books(list_type)

    sql = <<~SQL
      #{@condition}
      LIMIT $1
      OFFSET $2
    SQL

    results =
      if list_type == 'checked_out'
        query(sql, data[:limit], data[:offset], data[:user_id])
      else
        query(sql, data[:limit], data[:offset])
      end

    results.map do |result|
      data = {
        id: result['id'],
        title: result['title'],
        author: result['author'],
        checked_out: result['checked_out'],
        checked_out_user_id: result['checked_out_user_id'],
        date_checked_out: result['date_checked_out']
      }

      Book.new(data)
    end
  end

  def generate_sql_for_grab_books(list_type)
    case list_type
    when 'checked_out'
      <<~SQL
        SELECT id, title, author, checked_out, checked_out_user_id, date_checked_out FROM books
        WHERE checked_out_user_id = $3
        ORDER BY date_checked_out ASC
      SQL
    when 'available'
      <<~SQL
        SELECT id, title, author, checked_out, checked_out_user_id FROM books
        WHERE checked_out = 'f'
        ORDER BY title
      SQL
    else
      <<~SQL
        SELECT id, title, author, checked_out, checked_out_user_id FROM books
        ORDER BY title, checked_out
      SQL
    end
  end

  # finds the total number of books within a certain list_type and returns it as an integer (used in pagination)
  def total_book_count(data)
    list_type = data[:list_type]
    sql = generate_sql_for_total_book_cout(list_type)

    results = 
      if list_type == 'checked_out'
        query(sql, data[:user_id])
      else
        query(sql)
      end

    results.field_values('count').first.to_i
  end

  def generate_sql_for_total_book_cout(list_type)
    case list_type
    when 'checked_out'
      <<~SQL
        SELECT count(id) FROM books
        WHERE checked_out_user_id = $1
      SQL
    when 'available'
      <<~SQL
        SELECT count(id) FROM books
        WHERE checked_out = 'f'
      SQL
    else
      <<~SQL
        SELECT count(id) FROM books
      SQL
    end
  end

  # finds the number of books on any given page, returns integer. Page number is within the passed in 'data' hash. (used in pagination)
  def books_per_page(data)
    @condition = books_per_page_condition(data[:list_type])

    sql = <<~SQL
      #{@condition}
      LIMIT $1
      OFFSET $2
    SQL

    results =
      if data[:list_type] == 'checked_out'
        query(sql, data[:limit], data[:offset], data[:user_id])
      else
        query(sql, data[:limit], data[:offset])
      end

    results.field_values('count').first.to_i
  end
  
# returns the SQL needed for the query based on the given list type.
  def books_per_page_condition(list_type)
    case list_type
    when 'checked_out'
      <<~SQL
        SELECT count(id) FROM books
        WHERE checked_out_user_id = $3
      SQL
    when 'available'
      <<~SQL
        SELECT count(id) FROM books
        WHERE checked_out = 'f'
      SQL
    else
      <<~SQL
        SELECT count(id) FROM books
      SQL
    end
  end

  # updates the status of a book to checked_out = false, etc
  def return_book(user_id, book_id)
    sql = <<~SQL
      UPDATE books SET checked_out = false, checked_out_user_id = NULL, date_checked_out = NULL
      WHERE checked_out_user_id = $1 AND id = $2;
    SQL

    query(sql, user_id, book_id)
  end

  # updated book status checked_out = true, etc
  def checkout_book(user_id, book_id)
    sql = <<~SQL
      UPDATE books SET checked_out = true, checked_out_user_id = $1, date_checked_out = now()::date
      WHERE id = $2;
    SQL
    query(sql, user_id, book_id)
  end

  # checks to see if a user has any checked out books (used when deleting a user)
  def no_checked_out_books?(user_id)
    sql = <<~SQL
      SELECT count(b.id) FROM books AS b
      JOIN users AS u ON u.id = b.checked_out_user_id
      WHERE u.id = $1;
    SQL

    query(sql, user_id).first['count'].to_i.zero?
  end
end

# This class is used to store user info from the DB to the app.
class User
  attr_reader :first_name, :last_name, :admin

  def initialize(id, first_name, last_name, admin)
    @id = id,
    @first_name = first_name.capitalize,
    @last_name  = last_name.capitalize,
    @admin      = admin == 't'
  end

  def name
    "#{first_name} #{last_name}"
  end

  # this may seem like a strange method,
  # but for reasons I could not figure out the the instance variable @id
  # is an array [id, first_name, last_name] and so to pull the id from it this method is needed.
  def id
    @id.first
  end
end

# This class is used to store book info from the DB to the app.
class Book
  attr_reader :id, :title, :author, :checked_out, :checked_out_user_id, :date_checked_out

  def initialize(data)
    @id = data[:id]
    @title = data[:title]
    @author = data[:author]
    @checked_out = data[:checked_out]
    @checked_out_user_id = data[:checked_out_user_id]# .empty? ? nil : data[:checked_out_user_id]
    @date_checked_out = data[:date_checked_out]# .empty? ? nil : data[:checked_out_user_id]
  end
end
