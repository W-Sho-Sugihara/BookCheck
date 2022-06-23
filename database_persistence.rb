require 'pg'
require 'bcrypt'

require 'pry'

class DatabasePersistence
  def initialize(logger)
    @db = PG.connect(dbname: "library")
    @logger = logger
  end

  def query(sql, *params)
    @logger.info "#{sql}: #{params}"
    @db.exec_params(sql, params)
  end

  # def conditional_count_books_query(condition, *params)
  #   sql = <<~SQL
  #     SELECT count(id) FROM books
  #     #{condition};
  #     SQL

  #   @db.exec_params(sql, params)
  # end

  def disconnect
    @db.close
  end

  def find_id_num_user(id_num)
    sql = "SELECT id, password FROM users WHERE id = $1"
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

  def find_user(id_number)
    sql = "SELECT id, first_name, last_name, admin FROM users WHERE id = $1;"
    result = query(sql, id_number).first

    return nil unless result != nil
    id = result["id"]
    first_name = result["first_name"]
    last_name = result["last_name"]
    admin = result["admin"]
    
    User.new(id, first_name, last_name, admin)
    
  end
  
  def find_book(book_id)
    sql = <<~SQL
    SELECT * FROM books
    WHERE id = $1;
    SQL
    
    result = query(sql, book_id).first
    id = result["id"]
    title = result["title"]
    author = result["author"]
    checked_out = result["checked_out"] == 't'
    checked_out_user_id = result["checked_out_user_id"]
    date_checked_out = result["date_checked_out"]
    
    Book.new(id, title, author, checked_out, checked_out_user_id, date_checked_out)
  end
  
  def add_new_book(title, author)
    sql = <<~SQL
      INSERT INTO books (title, author)
      VALUES ($1, $2);
    SQL

    query(sql, title, author)
  end

  def update_book_info(book_id, title, author, checked_out, checked_out_user_id, date_checked_out)
    sql = <<~SQL
      UPDATE books SET title = $1, author = $2, checked_out = $3, checked_out_user_id = $4, date_checked_out = $5
      WHERE id = $6
    SQL

    query(sql, title, author, checked_out, checked_out_user_id, date_checked_out, book_id)
  end

  def delete_book(book_id)
    info = query("SELECT title, author FROM books WHERE id = $1", book_id).first.values
    sql = <<~SQL
      DELETE FROM books
      WHERE id = $1
    SQL

    query(sql, book_id)
    info
  end
  
  def new_user_unique?(first_name, last_name, password)
    sql =<<~SQL
    SELECT * FROM users 
    WHERE first_name LIKE $1 AND last_name LIKE $2;
    SQL
    results = query(sql, first_name, last_name)
    
    return true if results.first == nil
    results.all? do |result|
      BCrypt::Password.new(result["password"]) != password
    end
  end
  
  def encrypt_password(password)
    BCrypt::Password.create(password)
  end
  
  def create_new_user(first_name, last_name, password)
    crypt_password = encrypt_password(password)
    sql = <<~SQL
    INSERT INTO users(first_name, last_name, password)
    VALUES($1, $2, $3)
    SQL
    query(sql, first_name, last_name, crypt_password)
    
    sql_new_user_id = <<~SQL
    SELECT id FROM users  
    WHERE first_name LIKE $1 AND 
    last_name LIKE $2 AND password LIKE $3;
    SQL
    query(sql_new_user_id, first_name, last_name, crypt_password).values.first.first
  end
  
  def edit_user_info(id, first_name, last_name)
    sql = <<~SQL
      UPDATE users
        set first_name = $1, last_name = $2
        Where id = $3;
    SQL

    query(sql, first_name.capitalize, last_name.capitalize, id.to_i)
  end

  def delete_user(user_id)
    sql = <<~SQL
      DELETE FROM users WHERE id = $1;
    SQL
    query(sql, user_id)
  end

  def grab_books_from_db(data)
    if data[:list_type] == 'checked_out'
      @condition = <<~SQL
      SELECT id, title, author, checked_out, checked_out_user_id, date_checked_out FROM books
      WHERE checked_out_user_id = $3
      ORDER BY date_checked_out ASC
      SQL
    elsif data[:list_type] == 'available'
      @condition = <<~SQL
      SELECT id, title, author, checked_out, checked_out_user_id FROM books
      WHERE checked_out = 'f'
      ORDER BY title
      SQL
    else
      @condition = <<~SQL
      SELECT id, title, author, checked_out, checked_out_user_id FROM books
      ORDER BY title, checked_out
      SQL
    end
  
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

    results.map do |result|
      id = result["id"]
      title = result["title"]
      author = result["author"]
      checked_out = result["checked_out"]
      checked_out_user_id = result["checked_out_user_id"]
      date_checked_out = result["date_checked_out"]
      Book.new(id, title, author, checked_out, checked_out_user_id, date_checked_out)
    end
  end

  def total_book_count(data)
    # case list_type
    # when 'available'
    #   condition = "WHERE checked_out = 'f'"
    #   conditional_count_books_query(condition).values.first.first.to_i
    # when 'checked_out'
    #   condition = "WHERE checked_out = 't' AND checked_out_user_id = $1"
    #   conditional_count_books_query(condition, user_id).values.first.first.to_i
    # else
    #   condition = ''
    #   conditional_count_books_query(condition).values.first.first.to_i
    # end
    if data[:list_type] == 'checked_out'
      @sql = <<~SQL
      SELECT count(id) FROM books
      WHERE checked_out_user_id = $1
      SQL
    elsif data[:list_type] == 'available'
      @sql = <<~SQL
      SELECT count(id) FROM books
      WHERE checked_out = 'f'
      SQL
    else
      @sql = <<~SQL
      SELECT count(id) FROM books
      SQL
    end

    results = 
    if data[:list_type] == 'checked_out'
      query(@sql, data[:user_id])
    else
      query(@sql)
    end

    results.field_values('count').first.to_i
  end

  def books_per_page(data)
    if data[:list_type] == 'checked_out'
      @condition = <<~SQL
      SELECT count(id) FROM books
      WHERE checked_out_user_id = $3
      SQL
    elsif data[:list_type] == 'available'
      @condition = <<~SQL
      SELECT count(id) FROM books
      WHERE checked_out = 'f'
      SQL
    else
      @condition = <<~SQL
      SELECT count(id) FROM books
      SQL
    end

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

  def return_book(user_id, book_id)
    sql = <<~SQL
      UPDATE books SET checked_out = false, checked_out_user_id = NULL, date_checked_out = NULL
      WHERE checked_out_user_id = $1 AND id = $2;
    SQL

    query(sql, user_id, book_id)
  end

  def checkout_book(user_id, book_id)
    sql = <<~SQL
      UPDATE books SET checked_out = true, checked_out_user_id = $1, date_checked_out = now()::date
      WHERE id = $2;
    SQL
    query(sql, user_id, book_id)
  end

  def no_checked_out_books?(user_id)
    sql = <<~SQL
      SELECT count(b.id) FROM books AS b
      JOIN users AS u ON u.id = b.checked_out_user_id
      WHERE u.id = $1;
    SQL

    query(sql, user_id).first['count'].to_i == 0
  end
end

class User
  attr_reader :first_name, :last_name, :admin

  def initialize(id, first_name, last_name, admin)
    @id = id,
    @first_name = first_name.capitalize,
    @last_name = last_name.capitalize,
    @admin = admin == 't'
  end

  def name
    "#{first_name} #{last_name}"
  end

  def id
    @id.first
  end
end

class Book
  attr_reader :id, :title, :author, :checked_out, :checked_out_user_id, :date_checked_out

  def initialize(id, title, author, checked_out = nil, checked_out_user_id = nil, date_checked_out = nil)
    @id = id
    @title = title
    @author = author
    @checked_out = checked_out
    @checked_out_user_id = checked_out_user_id
    @date_checked_out = date_checked_out
  end
end