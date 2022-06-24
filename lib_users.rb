require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'tilt/erubis'

require_relative 'database_persistence'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'database_persistence.rb'
end

before do
  @storage = DatabasePersistence.new(logger)
  @user = session[:current_user]
end

after do
  @storage.disconnect
end

# ===== Display Helpers =====

helpers do
  # toggle display of login and logout icons
  def display_current_nav_icons
    if session[:logged_in] == true
      <<~HTM
        <a class="logout" href='/user/#{@user.id}/logout'>
          <img class="nav_icon  icon-logout" src="/images/logout_icon.svg" /></a>
      HTM
    else
      <<~HTM
        <a class="login" href="/user/login">
          <img class="nav_icon  icon-login" src="/images/login_icon.svg" /></a>
      HTM
    end
  end

  def display_books(data)
    books = @storage.grab_books_from_db(data)
    generate_books_html(books, data)
  end
end

# ===== PAGINATION HELPER METHODS =====

# main html template for books object
def generate_books_html(books, data)
  unless valid_page_number?(data)
    return "<div class='flash error'><p class='invalid-page'>Not a valid page number.</p></div>"
  end
  if books.empty? && data[:list_type] == 'checked_out'
    return '<span>You currently have 0 books checked out.</span>'
  elsif books.empty? && data[:list_type] == 'available'
    return '<span>Sorry, there are currently no available books.</span>'
  end

  books_html = generate_book_objs_html(books, data)

  "<table class='container-books-list'> <tbody>#{books_html.join}</tbody></table>"
end

# html template for each book obj
def generate_book_objs_html(books, data)
  books.map do |book|
    <<~HTM
      <tr class='book-object'> 
        <td>
          <img class="book-icon" src="/images/book_icon.svg">
        </td>
        <td>
          <section class="book-info">
            <span>#{book.title}</span>
            <span>By: #{book.author}</span>
            #{if data[:list_type] == 'all'
                "<span>Available: #{book.checked_out == 't' ? 'No' : 'Yes'}</span>"
              elsif data[:list_type] == 'checked_out'
                "<span>Date Checked Out: #{book.date_checked_out}</span>"
              end}
          </section>
        </td>
        <td>
          #{generate_book_obj_buttons(book)}
        </td> 
      </tr>
    HTM
  end
end

# generates the book obj buttons (check out, return, edit)
def generate_book_obj_buttons(book)
  <<~HTM
    <table><tbody>
      #{if book.checked_out == 't' && book.checked_out_user_id.to_i == @user.id.to_i
          "<tr><td><form action='/user/#{params[:user_id]}/books/#{book.id}/return' method='post'><button type='submit' class='btn btn-return'>Return</button></form></td></tr>"
        elsif book.checked_out == 'f'
          "<tr><td><form action='/user/#{params[:user_id]}/books/#{book.id}/checkout' method='post'><button type='submit' class='btn btn-checkout'>Checkout</button></form></td></tr>"
        end
      }
      #{if @user.admin
          "<tr><td><a href='/books/admin_user/#{params[:user_id]}/book/#{book.id}/edit'><button class='btn btn-return'>Edit Book Info</button></a></td></tr>"
        end
      }
    </tbody></table>
  HTM
end

# html template for pagination nav bar, next and previous buttons
def generate_pagination_buttons(data)
  return unless valid_page_number?(data)

  book_count = @storage.total_book_count(data)
  total_pages = (book_count / data[:limit].to_f).ceil
  <<~HTM
    <span class="#{'btn-hidden' if hide_previous_btn?(data)}">
      <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{data[:page] - 1}"><button  class="btn">Previous 10</button></a>
    </span>
    #{page_nums(total_pages, data)}
    <span class="#{'btn-hidden' if hide_next_btn?(data)}">
      <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{data[:page] + 1}"><button class="btn">Next 10</button></a>
    </span>
  HTM
end

# html template for generating page numbers within pagination nav bar
def page_nums(total_pages, data)
  (1..total_pages).to_a.map do |page_num|
    <<~HTM
      <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{page_num}">
      <button #{'disabled' if page_num == data[:page]} class="btn-page-num ">#{page_num}</button></a>
    HTM
  end.join
end

# ===== HELPER METHODS =====

# currently logged in validation
def currently_logged_in
  session[:logged_in] == true
end

# login attempt validation
def login_successful?(id_num, password)
  # if password matches the id num then login successful
  @storage.id_num_matches_password?(id_num, password)
end

# validate user id num in the URL
def validate_user_id(user_id)
  @user.id == user_id
end

# input validations
def empty_login_inputs?(user_id, password)
  user_id.empty? || password.empty?
end

# input validations
def valid_new_user_inputs?(first_name, last_name, password1, password2)
  valid_name_length?(first_name, last_name) &&
  valid_password_length?(password1, password2) &&
  passwords_equal?(password1, password2)
end

# input validations
def inputs_empty?(inputs)
  inputs.any?(&:empty?)
end

# input validations
def valid_name_length?(first_name, last_name)
  first_name.length.positive? && last_name.length.positive?
end

# input validations
def valid_password_length?(password1, password2)
  password1.length >= 8 && password2.length >= 8
end

# input validations
def passwords_equal?(password1, password2)
  password1 == password2
end

# input validations
def new_user_unique?(first_name, last_name, password1)
  @storage.new_user_unique?(first_name, last_name, password1)
end

# edit and add book info validations
def empty_title_or_author?(title, author)
  title.empty? || author.empty?
end

# edit book info validations
def checked_out_book_info_valid?(checked_out, checked_out_user_id, date_checked_out)
  if checked_out == false
    checked_out_user_id.nil? &&
      date_checked_out.nil?
  elsif checked_out == true
      !@storage.find_user(checked_out_user_id).nil? &&
      !date_checked_out.empty?
  end
end

# update the current user within sessions
def update_current_user(user_id)
  session[:current_user] = @storage.find_user(user_id)
end

# pagination helper method (alters the button class, helps toggles visibility)
def hide_previous_btn?(data)
  data[:page] <= 1
end

# pagination helper method (alters the button class, helps toggles visibility)
def hide_next_btn?(data)
  (@storage.total_book_count(data) / data[:limit].to_f).ceil <= data[:page]
end

# helps validate the page number in the params
def valid_page_number?(data)
  @storage.books_per_page(data)
end

# checks for any checked out books
def no_checked_out_books?(user_id)
  @storage.no_checked_out_books?(user_id)
end

# validation for book existance
def book_doesnt_exist(book_id)
  @storage.find_book(book_id).nil?
end

# ========== ROUTES ==========

# home
get '/' do
  session[:error_message] = 'Please login to continue.' unless currently_logged_in
  redirect '/user/login'
end

# user login route
get '/user/login' do
  if currently_logged_in # cannot go to login page if already logged in
    redirect "/user/#{@user.id}/home"
  else
    erb :login
  end
end

# user login route. Has input validations
# and will redirect to a previous page if
# direct URL was passed to try to go to a restricted page.
post '/user/login' do
  if empty_login_inputs?(params[:id_number], params[:password])
    session[:error_message] = 'ID and/or Password cannot be empty.'
    redirect '/user/login'
  elsif login_successful?(params[:id_number], params[:password])
    session[:logged_in] = true
    session[:success_message] = 'Login Successful'
    session[:current_user] = @storage.find_user(params[:id_number])

    redirect session.delete(:last_response) if session[:last_response]

    redirect "/user/#{session[:current_user].id}/home"
  else
    session[:error_message] = 'Invalid id Number and/or Password.'
    redirect '/user/login'
  end
end

# user logout route with current login validation
get '/user/:user_id/logout' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    session[:logged_in] = false
    session[:current_user] = nil
    erb :logout
  else
    session[:error_message] = 'You must be logged in to log out.'
    redirect '/user/login'
  end
end

# create new user page
get '/user/new' do
  erb :new_user
end

# create new user route with input validations and unique new user info validation
post '/user/new' do
  inputs = [params[:first_name].capitalize,
            params[:last_name].capitalize,
            params[:password1],
            params[:password2]]

  new_user_unique = new_user_unique?(*inputs[0..2])

  if valid_new_user_inputs?(*inputs) && new_user_unique
    first_name = params[:first_name].capitalize
    last_name = params[:last_name].capitalize
    password = params[:password1]
    @new_user_id = @storage.create_new_user(first_name, last_name, password)
    redirect "/user/new/#{@new_user_id}/welcome"
  else
    if inputs_empty?(inputs)
      session[:error_message] = 'Inputs cannot be empty.'
    elsif !new_user_unique
      session[:error_message] = 'Please choose unique credentials.'
    else
      session[:error_message] = 'Passwords do not match.'
    end
    erb :new_user
  end
end

# welcome page for new user, with validation
get '/user/new/:user_id/welcome' do
  @user = @storage.find_user(params[:user_id])

  if @user.nil?
    session[:error_message] = "I'm sorry, but you don't exist yet. Please create an account or login."
    erb :login
  else
    erb :welcome_new_user
  end
end

# home page for successful logins with user login and current user matches URL user id validation
get '/user/:user_id/home' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    erb :home
  else
    session[:error_message] = 'Please login to continue.'
    session[:last_response] = "/user/#{user_id}/home"
    erb :login
  end
end

# edit the names of current user page with user login and current user matches URL user id validation
get '/user/:user_id/edit' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    erb :edit_user
  else
    session[:error_message] = 'Please login to continue.'
    session[:last_response] = "/user/#{user_id}/edit"

    erb :login
  end
end

# edit the names of current user with input validations
post '/user/:user_id/edit' do
  first_name = params[:first_name]
  last_name = params[:last_name]
  user_id = params[:user_id]

  if valid_name_length?(first_name, last_name)
    @storage.edit_user_info(user_id, first_name, last_name)
    update_current_user(user_id)
    session[:success_message] = 'Edit was successful.'
    redirect "/user/#{user_id}/home"
  else
    session[:error_message] = 'New names cannot be empty.'
    erb :edit_user
  end
end

# delete the current logged in user with user login and current user matches URL user id validation
post '/user/:user_id/delete' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif !currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Must be logged in to delete account.'
    session[:last_response] = "/user/#{user_id}/edit"
    erb :login
  elsif no_checked_out_books?(user_id) && validate_user_id(user_id)
    @storage.delete_user(user_id)
    session[:current_user] = nil
    session[:logged_in] = false
    session[:success_message] = 'Account successfully deleted.'
    redirect '/user/login'
  else
    session[:error_message] = 'Cannot delete account with checked out books.'
    redirect "/user/#{user_id}/edit"
  end
end

# as admin, add new book to the library with user login, current user matches URL user id and admin status validation
get '/books/admin_user/:user_id/book/add' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && !@user.admin
    session[:error_message] = 'You must be an administrator to edit books.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && @user.admin
    @title = 'Add New Book'
    erb :book_info
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{params[:list_type]}/edit"
    session[:error_message] = 'Please login to continue.'
    redirect '/user/login'
  end
end

# route to add new book to library with input vaidations
post '/books/admin_user/:user_id/book/add' do
  title = params[:title].split(' ').map(&:capitalize).join(' ')
  author = params[:author].split(' ').map(&:capitalize).join(' ')
  # checked_out = params[:checked_out] == 't'
  # checked_out_user_id = params[:checked_out_user_id]
  # date_checked_out = params[:date_checked_out]

  if empty_title_or_author?(title, author)
    session[:error_message] = 'Book title and author cannot be empty.'
    redirect back
  end

  @storage.add_new_book(title, author)
  session[:success_message] = "Successfully added '#{title}' by: #{author} to library."

  redirect "/books/admin_user/#{params[:user_id]}/book/add"
end

# as admin edit book info with user login, current user matches URL user id and admin status validation
get '/books/admin_user/:user_id/book/:book_id/edit' do
  user_id = params[:user_id]
  book_id = params[:book_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && !@user.admin
    session[:error_message] = 'You must be an administrator to edit books.'
    redirect back
  elsif book_doesnt_exist(book_id)
    session[:error_message] = 'The specified book does not exist.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && @user.admin
    @title = 'Edit Book Info'
    @book = @storage.find_book(book_id)
    erb :book_info
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{book_id}/edit"
    session[:error_message] = 'Please login to continue.'
    redirect '/user/login'
  end
end

# route to add book to DB with input validation
post '/books/admin_user/:user_id/book/:book_id/edit' do
  new_book_info = {
    book_id: params[:book_id],
    title: params[:title],
    author: params[:author],
    checked_out: params[:checked_out] == 't' || params[:checked_out] == 'true',
    checked_out_user_id: params[:checked_out_user_id].empty? ? nil : params[:checked_out_user_id].to_i,
    date_checked_out: params[:date_checked_out].empty? ? nil : params[:date_checked_out]
  }
  

  if empty_title_or_author?(new_book_info[:title], new_book_info[:author]) ||
     !checked_out_book_info_valid?(new_book_info[:checked_out], new_book_info[:checked_out_user_id], new_book_info[:date_checked_out])
    session[:error_message] = <<~STR
      Invalid Inputs. Inputs cannot be empty and/or conflict. 
      (eg. Title and author cannot be empty.  
      'Checked out' cannot be false when it has a 'Date checked out' value.)
    STR
    redirect "/books/admin_user/#{params[:user_id]}/book/#{new_book_info[:book_id]}/edit "
  end

  @title = 'Edit Book Info'
  @book = @storage.find_book(new_book_info[:book_id])
  @storage.update_book_info(new_book_info)
  session[:success_message] = <<~STR
    '#{@book.title}' by 
    #{@book.author.split(',').rotate(1).join(' ')} 
    has been successfully updated
  STR
  redirect "/books/admin_user/#{params[:user_id]}/book/#{new_book_info[:book_id]}/edit "
end

# route to delete book from DB with user login, current user matches URL user id and admin status validation
post '/books/admin_user/:user_id/book/:book_id/delete' do
  user_id = params[:user_id]
  book_id = params[:book_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && !@user.admin
    session[:error_message] = 'You must be an administrator to edit books.'
    redirect back
  elsif book_doesnt_exist(book_id)
    session[:error_message] = 'The specified book does not exist.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && @user.admin
    title, author = @storage.delete_book(book_id) # returns an array [title, author]
    session[:success_message] = "#{title} by: #{author.split(',').rotate(1).join(' ')} successfully deleted."
    erb :home
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{book_id}/edit"
    session[:error_message] = 'Please login to continue.'
    redirect '/user/login'
  end
end

# view book list within library based on selected list type with user login, current user matches URL user id validation
get '/books/:user_id/:list_type/:page' do
  user_id = params[:user_id]
  list_type = params[:list_type]
  page = params[:page]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    @title = "#{list_type.capitalize} Books"
    @data = {
      user_id: user_id,
      list_type: list_type,
      page: page.to_i,
      limit: 10,
      offset: page.to_i * 10 - 10
    }
    erb :books
  else
    session[:last_response] = "/books/#{user_id}/#{list_type}/#{page}"
    session[:error_message] = 'Please login to continue.'
    redirect '/user/login'
  end
end

# view checked out book list specific to a user with user login, current user matches URL user id and validation
get '/user/:user_id/books/:list_type/:page' do
  user_id = params[:user_id]
  list_type = params[:list_type]
  page = params[:page]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    @title = "Books Currently Checked out by: #{@user.name}"
    @data = {
      user_id: user_id,
      list_type: list_type,
      page: page.to_i,
      limit: 10,
      offset: page.to_i * 10 - 10
    }
    erb :books
  else
    session[:last_response] = "/user/#{user_id}/books/#{list_type}/#{page}"
    session[:error_message] = 'Please login to continue.'
    redirect '/user/login'
  end
end

# route returns books
post '/user/:user_id/books/:book_id/return' do
  user_id = params[:user_id]
  book_id = params[:book_id]
  @storage.return_book(user_id, book_id)
  redirect back
end

# route checks out available books to the current user
post '/user/:user_id/books/:book_id/checkout' do
  user_id = params[:user_id]
  book_id = params[:book_id]
  @storage.checkout_book(user_id, book_id)
  redirect back
end
