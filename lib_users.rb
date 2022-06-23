require "sinatra"
require "sinatra/content_for"
require "sinatra/reloader"
require "tilt/erubis"

require_relative 'database_persistence'

configure do
  enable :sessions
  set :session_secret, "secret"
  set :erb, escape_html: true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'database_persistence.rb'
end

before do
  @storage = DatabasePersistence.new(logger)
  @user = session[:current_user]
  logger.info(session)
end

after do
  logger.info(session)
  @storage.disconnect
end

helpers do
  # toggle display of login and logout icons
  def display_current_nav_icons
    if session[:logged_in] == true
      <<~HTM
      <a class="logout" href='/user/#{@user.id}/logout'>
        <img class="nav_icon  icon-logout" src="/images/logout_icon.svg" />
      </a>
      HTM
    else
      <<~HTM
      <a class="login" href="/user/login">
        <img class="nav_icon  icon-login" src="/images/login_icon.svg" />
      </a>
      HTM
    end
  end

  # ===== PAGINATION METHODS =====

  def display_books(data)
    books = @storage.grab_books_from_db(data)
    generate_books_html(books, data)

  end

  def generate_books_html(books, data)
    if !valid_page_number?(data)
      return "<div class='flash error'><p class='invalid-page'>Not a valid page number.</p></div>"
    elsif books.empty? && data[:list_type] == 'checked_out'
      return "<span>You currently have 0 books checked out.</span>" 
    elsif books.empty? && data[:list_type] == 'available'
      return "<span>Sorry, there are currently no available books.</span>"
    end
    books_html = books.map do |book|
      book_obj = <<~HTM
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
        </td> 
      </tr>
      HTM
    end
    "<table class='container-books-list'> <tbody>#{books_html.join}</tbody></table>"
  end

  def generate_pagination_buttons(data)
    unless valid_page_number?(data)
      return
    end
    book_count = @storage.total_book_count(data)
    total_pages = (book_count/(data[:limit].to_f)).ceil
    <<~HTM
    <span class="#{'btn-hidden' if hide_previous_btn?(data)}">
      <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{data[:page] - 1}"><button class="btn">Previous 10</button></a>
    </span>
    #{ (1..total_pages).to_a.map do |page_num|
      <<~HTM
        <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{page_num}"><button #{'disabled' if page_num == data[:page]} class="btn-page-num ">#{page_num}</button></a>
      HTM
    end.join()}
    <span class="#{'btn-hidden' if hide_next_btn?(data)}">
      <a class="" href="/books/#{data[:user_id]}/#{data[:list_type]}/#{data[:page] + 1}"><button class="btn">Next 10</button></a>
    </span>
    HTM
  end
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

def valid_new_user_inputs?(first_name, last_name, password1, password2)
  valid_name_length?(first_name, last_name) &&
  valid_password_length?(password1, password2) &&
  passwords_equal?(password1, password2)
end

def valid_name_length?(first_name, last_name)
  first_name.length > 0 &&
  last_name.length > 0
end

def valid_password_length?(password1, password2)
  password1.length >= 8 &&
  password2.length >= 8
end

def passwords_equal?(password1, password2)
  password1 == password2
end

def new_user_unique?(first_name, last_name, password1, password2)
  @storage.new_user_unique?(first_name, last_name, password1)
end

# edit and add book info validations

def empty_title_or_author?(title, author)
  title.empty? || author.empty?
end

def edit_checked_out_book_info_valid?(checked_out, checked_out_user_id, date_checked_out)
  if checked_out == false
    checked_out_user_id == nil && 
    date_checked_out == nil
  elsif checked_out == true
    checked_out_user_id.instance_of?(Integer) && 
    @storage.find_user(checked_out_user_id) &&
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

# ========== ROUTES ==========

# home
get "/" do
  session[:error_message] = "Please login to continue." unless currently_logged_in
  redirect "/user/login"
end

# user login route
get "/user/login" do
  if currently_logged_in # cannot go to login page is already logged in
    redirect "/user/#{@user.id}/home"
  else  
    erb :login
  end
end

post '/user/login' do
  if empty_login_inputs?(params[:id_number], params[:password])
    session[:error_message] = "ID and/or Password cannot be empty."
    redirect "/user/login"
  elsif login_successful?(params[:id_number], params[:password])
    session[:logged_in] = true
    session[:success_message] = "Login Successful"
    session[:current_user] = @storage.find_user(params[:id_number])

    redirect session.delete(:last_response) if session[:last_response]

    redirect "/user/#{session[:current_user].id}/home"
  else
    session[:error_message] = 'Invalid id Number and/or Password.'
    redirect "/user/login"
  end
end

# user logout route
get "/user/:user_id/logout" do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    session[:logged_in] = false
    session[:current_user] = nil
    erb :logout
  else
    session[:error_message] = "You must be logged in to log out."
    redirect '/user/login'
  end
end

# create new user page
get "/user/new" do
  erb :new_user
end

# create new user route
post "/user/new" do
  inputs = [params[:first_name].capitalize,
            params[:last_name].capitalize,
            params[:password1],
            params[:password2]]

  new_user_unique = new_user_unique?(*inputs)

  if valid_new_user_inputs?(*inputs) && new_user_unique
    first_name = params[:first_name].capitalize
    last_name = params[:last_name].capitalize
    password = params[:password1]
    @new_user_id = @storage.create_new_user(first_name, last_name,  password)
    
    redirect "/user/new/#{@new_user_id}/welcome"
  else
    if inputs.any?(&:empty?)
        session[:error_message] = "Inputs cannot be empty."
    elsif !new_user_unique
      session[:error_message] = "Please choose a unique password."
    else
      session[:error_message] = "Passwords do not match."
    end
    erb :new_user
  end
end

# welcome page for new user
get "/user/new/:user_id/welcome" do
  @user = @storage.find_user(params[:user_id])

  if @user == nil
    session[:error_message] = "I'm sorry, but you don't exist yet. Please create an account or login."
    erb :login
  else
    erb :welcome_new_user
  end
end

# home page for successful logins
get "/user/:user_id/home" do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    erb :home
  else
    session[:error_message] = "Please login to continue."
    session[:last_response] = "/user/#{user_id}/home"
    erb :login
  end
end

# edit the names of current user page
get "/user/:user_id/edit" do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    erb :edit_user
  else
    session[:error_message] = "Please login to continue."
    session[:last_response] = "/user/#{user_id}/edit"

    erb :login
  end
end

# edit the names of current user
post "/user/:user_id/edit" do
  first_name = params[:first_name]
  last_name = params[:last_name]
  user_id = params[:user_id]

  if valid_name_length?(first_name, last_name)
    @storage.edit_user_info(user_id, first_name, last_name)
    update_current_user(user_id)
    session[:success_message] = "Edit was successful."
    redirect "/user/#{user_id}/home"
  else
    session[:error_message] = "New names cannot be empty."
    erb :edit_user
  end
end

# delete the current logged in user
post '/user/:user_id/delete' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif !currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Must be logged in to delete account."
    session[:last_response] = "/user/#{user_id}/edit"
    erb :login
  elsif no_checked_out_books?(user_id) && validate_user_id(user_id)
    @storage.delete_user(user_id)
    session[:current_user] = nil
    session[:logged_in] = false
    session[:success_message] = "Account successfully deleted."
    redirect '/user/login'
  else
    session[:error_message] = "Cannot delete account with checked out books."
    redirect "/user/#{user_id}/edit"
  end
end

# as admin, add new book to the library
get '/books/admin_user/:user_id/book/add' do
  user_id = params[:user_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    session[:error_message] = "You must be an administrator to edit books." unless @user.admin
    @title = "Add New Book"
    erb :book_info
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{params[:list_type]}/edit"
    session[:error_message] = "Please login to continue."
    redirect "/user/login"
  end
end

# route to add new book to library
post '/books/admin_user/:user_id/book/add' do
  title = params[:title].split(' ').map(&:capitalize).join(' ')
  author = params[:author].split(' ').map(&:capitalize).join(' ')
  checked_out = params[:checked_out] == 't'
  checked_out_user_id = params[:checked_out_user_id]
  date_checked_out = params[:date_checked_out]

  if empty_title_or_author?(title, author)
    session[:error_message] = "Book title and author cannot be empty."
    redirect back
  end

  @storage.add_new_book(title, author)
  session[:success_message] = "Successfully added '#{title}' by: #{author} to library."

  redirect "/books/admin_user/#{params[:user_id]}/book/add"
end

# as admin edit book info
get '/books/admin_user/:user_id/book/:book_id/edit' do
  user_id = params[:user_id]
  book_id = params[:book_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id)
    session[:error_message] = "You must be an administrator to edit books." unless @user.admin
    @title = "Edit Book Info"
    @book = @storage.find_book(book_id)
    erb :book_info
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{book_id}/edit"
    session[:error_message] = "Please login to continue."
    redirect "/user/login"
  end
end

# route to add book to DB with validations
post '/books/admin_user/:user_id/book/:book_id/edit' do
  book_id = params[:book_id]
  title = params[:title]
  author = params[:author]
  checked_out = params[:checked_out] == 't' || params[:checked_out] == 'true'
  checked_out_user_id = params[:checked_out_user_id].empty? ? nil : params[:checked_out_user_id].to_i
  date_checked_out = params[:date_checked_out].empty? ? nil : params[:date_checked_out]

  if empty_title_or_author?(title, author) ||
    !edit_checked_out_book_info_valid?(checked_out, checked_out_user_id, date_checked_out)
    session[:error_message] = "Invalid Inputs. Inputs cannot be empty and/or conflict. (eg. Title and author cannot be empty. 'Checked out' cannot be false when it has a 'Date checked out' value.)"
    redirect "/books/#{params[:user_id]}/book/#{book_id}/edit "
  end

  @storage.update_book_info(book_id, title, author, checked_out, checked_out_user_id, date_checked_out)
  session[:success_message] = "'#{@storage.find_book(book_id).title}' by #{@storage.find_book(book_id).author} has been successfully updated."
  @title = "Edit Book Info"
  @book = @storage.find_book(book_id)
  erb :book_info
end

post '/books/admin_user/:user_id/book/:book_id/delete' do
  user_id = params[:user_id]
  book_id = params[:book_id]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && !@user.admin
    session[:error_message] = "You must be an administrator to edit books."
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && @user.admin
    title, author = @storage.delete_book(book_id) # returns an array [title, author]
    session[:success_message] = "#{title} by: #{author} successfully deleted."
    erb :home
  else
    session[:last_response] = "/books/admin_user/#{user_id}/book/#{book_id}/edit"
    session[:error_message] = "Please login to continue."
    redirect "/user/login"
  end
  
end

# view book list within library based on selected list type
get "/books/:user_id/:list_type/:page" do
  user_id = params[:user_id]
  list_type = params[:list_type]
  page = params[:page]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
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
    session[:error_message] = "Please login to continue."
    redirect "/user/login"
  end
end

# view book list specific to a user (eg. checked out books)
get '/user/:user_id/books/:list_type/:page' do
  user_id = params[:user_id]
  list_type = params[:list_type]
  page = params[:page]

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = "Wrong user ID in URL."
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
    session[:error_message] = "Please login to continue."
    redirect "/user/login"
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


