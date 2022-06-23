# ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'pg'
require 'bcrypt'

require_relative '../lib_users.rb'
require_relative '../database_persistence.rb'

class TestLibUsers < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # Helper methods

  def session
    last_request.env['rack.session']
  end

  def setup
    @storage = DatabasePersistence.new(rack.logger)
    init_test_user
  end

  def encrypt_password(password)
    BCrypt::Password.create(password)
  end

  def init_test_user
    password = encrypt_password('00000000')
    sql = "INSERT INTO users (id, first_name, last_name, password)
    VALUES (999999, 'test', 'testing', $1);"
    @storage.query(sql, password)
  end

  def delete_test_user
    sql = "DELETE FROM users WHERE id = 999999;"
    @storage.query(sql)
  end

  def teardown
    delete_test_user
    @storage.disconnect
  end


  # === TESTS ===

  def test_home
    get '/'

    assert_equal 302, last_response.status
    refute session[:logged_in]
  end

  def test_home_error_message
    get '/'
    assert session[:error_message]

    get '/user/login'
    refute session[:error_message]
  end

  def test_valid_login
    post "/user/login", {id_number: '999999', password: '00000000'}

    assert_equal 302, last_response.status
    assert session[:logged_in]
  end

  def test_wrong_login
    post "/user/login", {id_number: '999998', password: '00000000'}

    assert_equal 302, last_response.status
    refute session[:logged_in]
    assert_equal 'Invalid id Number and/or Password.', session[:error_message]
  end

  def test_empty_login
    post "/user/login", {id_number: '', password: ''}

    assert_equal 302, last_response.status
    refute session[:logged_in]
    assert_equal "ID and/or Password cannot be empty.", session[:error_message]
  end

  def test_create_new_user_page
    get "/user/new"

    assert_equal 200, last_response.status
  end

  def test_valid_create_new_user
    sql = "DELETE FROM users WHERE first_name LIKE 'John' AND last_name LIKE 'Doe';"
    @storage.query(sql)
    post "/user/new", {first_name:'John', last_name: 'Doe', password1:'alskdjfh', password2:'alskdjfh'}
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "Your new ID number is"

    sql = "DELETE FROM users WHERE first_name LIKE 'John' AND last_name LIKE 'Doe';"
    @storage.query(sql)

  end

  def test_create_duplicate_user
    delete_test_user
    init_test_user
    post "/user/new", {first_name:'test', last_name: 'testing', password1:'00000000', password2:'00000000'}
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "Given names and password already in use."
  end

end