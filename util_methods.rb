module ViewUtils
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
  if books.empty? && data[:list_type] == 'checked_out' && data[:page] == 1
    return '<span>You currently have 0 books checked out.</span>'
  elsif books.empty? && data[:list_type] == 'checked_out' && data[:page] != 1
    return '<span>No books on current page.</span>'
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
        elsif book.checked_out == 't'
          "<button class='btn-unavailable'>Unavailable</button>"
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

# edit checked out status of book validation
def valid_checked_out_input?(status)
  return true if status == 't' || status == 'true' || status == 'false' || status == 'f'
end

# edit book checked out user validation
def valid_checked_out_user_inputs?(user_id)
  !@storage.find_user(user_id).nil?
end
# edit book date checked out validation
def valid_checked_out_date_inputs?(date)
  date = date.split('-').map(&:to_i)
  Date.new(*date) <= Date.today
end

def empty_user_id_and_date?(user_id, date)
  user_id.nil? && date.nil?
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
  @storage.total_book_count(data) / data[:limit] + 1 >= data[:page]
end

# checks for any checked out books
def no_checked_out_books?(user_id)
  @storage.no_checked_out_books?(user_id)
end

# validation for book existance
def book_doesnt_exist(book_id)
  @storage.find_book(book_id).nil?
end

