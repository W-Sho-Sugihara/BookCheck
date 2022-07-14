require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader'
require 'tilt/erubis'

require_relative 'database_persistence'
require_relative 'util_methods'

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

helpers ViewUtils

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
    erb :login
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
    redirect '/user/login'
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
    redirect '/user/login'
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

    redirect '/user/login'
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
  @title = "Add New Book"

  if empty_title_or_author?(params[:title], params[:author])
    session[:error_message] = 'Book title and author cannot be empty.'
    erb :book_info
  else
    @storage.add_new_book(title, author)
    session[:success_message] = "Successfully added '#{title}' by: #{author} to library."
    # redirect "/books/admin_user/#{params[:user_id]}/book/add"
    redirect "/books/admin_user/#{params[:user_id]}/book/add"
  end
end

# as admin edit book info with user login, current user matches URL user id and admin status validation
get '/books/admin_user/:user_id/book/:book_id/edit' do
  user_id = params[:user_id]
  book_id = params[:book_id]
  @title = 'Edit Book Info'

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && !@user.admin
    session[:error_message] = 'You must be an administrator to edit books.'
    redirect back
  elsif (book_id =~ /[0-9]/).nil?
    session[:error_message] = "Book ID's must be integers."
    redirect back
  elsif book_doesnt_exist(book_id)
    session[:error_message] = 'The specified book does not exist.'
    redirect back
  elsif currently_logged_in && validate_user_id(user_id) && @user.admin
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
  @book = @storage.find_book(params[:book_id])
  @title = 'Edit Book Info'

  new_book_info = {
    book_id: params[:book_id],
    title: params[:title],
    author: params[:author],
    checked_out: params[:checked_out],
    checked_out_user_id: params[:checked_out_user_id].empty? ? nil : params[:checked_out_user_id].to_i,
    date_checked_out: params[:date_checked_out].empty? ? nil : params[:date_checked_out]
  }

  if empty_title_or_author?(new_book_info[:title], new_book_info[:author])
    session[:error_message] = 'Title and/or author cannto be empty.'
    erb :book_info
  elsif !valid_checked_out_input?(new_book_info[:checked_out])
    session[:error_message] = "The value for 'Checked Out' must be either 'true', 't', 'false' or 'f'."
    erb :book_info
  elsif (new_book_info[:checked_out] == 't' || new_book_info[:checked_out] == 'true') &&
    !valid_checked_out_user_inputs?(new_book_info[:checked_out_user_id])
      session[:error_message] = 'Entered User ID not valid.'
      erb :book_info
  elsif (new_book_info[:checked_out] == 't' || new_book_info[:checked_out] == 'true') &&
    !valid_checked_out_date_inputs?(new_book_info[:date_checked_out])
      session[:error_message] = 'Entered date connot be in the future.'
      erb :book_info
  elsif new_book_info[:checked_out] == 'f' || new_book_info[:checked_out] == 'false' &&
    !empty_user_id_and_date?(new_book_info[:checked_out_user_id], new_book_info[:date_checked_out])
      session[:error_message] = 'If not checked out, User ID and Date checked out must be empty.'
      erb :book_info
  else
    @storage.update_book_info(new_book_info)
    @book = @storage.find_book(new_book_info[:book_id])
    session[:success_message] = <<~STR
      '#{@book.title}' by 
      #{@book.author.split(',').rotate(1).join(' ')} 
      has been successfully updated
    STR
    redirect "/books/admin_user/#{params[:user_id]}/book/#{params[:book_id]}/edit"
  end
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
  elsif (book_id =~ /[0-9]/).nil?
    session[:error_message] = "Book ID's must be integers."
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
  @title = "#{list_type.capitalize} Books"

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    erb :books
  elsif (page =~ /[0-9]/).nil?
    session[:error_message] = 'Page numbers must be integers.'
    erb :books
  elsif page.to_i.zero?
    session[:error_message] = 'Page number cannot be 0.'
    erb :books
  elsif currently_logged_in && validate_user_id(user_id)
    
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
  @title = "Books Currently Checked out by: #{@user.name}"

  if currently_logged_in && !validate_user_id(user_id)
    session[:error_message] = 'Wrong user ID in URL.'
    erb :books
  elsif (page =~ /[0-9]/).nil?
    session[:error_message] = 'Page numbers must be integers.'
    erb :books
  elsif page.to_i.zero?
    session[:error_message] = 'Page number cannot be 0.'
    erb :books
  elsif currently_logged_in && validate_user_id(user_id)
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
