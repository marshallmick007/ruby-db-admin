require 'sequel'
require 'json'
require 'sinatra'
# require 'sinatra/reloader' if development? #NOTICE: For debug, you need uncomment this line and "gem 'sinatra-reloader'" in Gemfile.

DBs = []
# DB = Sequel.sqlite('ruby_db_admin.db') # ./ruby_db_admin.db
# DB = Sequel.connect({ adapter: 'postgres', user: 'user', password: '', host: 'host', port: 5432, database: 'database_name' }) # host can be IP or host_name.
# DB = Sequel.connect({ adapter: 'mysql2',   user: 'user', password: '', host: 'host', database: 'database_name' }) # adapter can also be 'postgres', 'sqlite', 'oracle', 'sqlanywhere', 'db2', 'informix' etc. We will use default port if port is nil.

set :bind, '0.0.0.0'

enable :sessions

get '/' do
  erb :index, layout: :index
end

get '/home' do
  erb :home
end

get '/tables/:table_name' do
  @schema = DB.schema(params[:table_name].to_sym)

  @dataset = DB[params[:table_name].to_sym].extension(:pagination)\
               .paginate((params[:page] || 1).to_i, 50, record_count=nil)

  erb :table
end

post '/connect_another_db' do
  begin
    another_db = Sequel.connect(connect_hash)
    if another_db.test_connection
      DB = another_db
      DBs << DB
    end
  rescue Sequel::Error::AdapterNotFound => e
    session[:error] = "#{e.message} \n Maybe you need install the database driver gem first.\n We suggest you read the 'Gemfile' of 'ruby-db-admin'.\n Then you will know how to install the driver gem."
  rescue Exception => e
    session[:error] = e.message
  end

  redirect '/home'
end

get '/switch_db/:i' do
  begin
    DB = DBs[params[:i].to_i] if DBs[params[:i].to_i].test_connection
  rescue Exception => e
    session[:error] = e.message
  end

  redirect '/home'
end


post '/tables/:table_name/insert_one' do
  content_type :json

  begin
    id = DB[params[:table_name].to_sym].insert(textarea_value_to_hash(params[:values]))

    { id: id }.to_json
  rescue Exception => e
    status 500
    { message: e.message }.to_json
  end
end

delete '/tables/:table_name/delete_one/:id' do
  DB[params[:table_name].to_sym].where(id: params[:id]).delete

  content_type :json
  { id: params[:id] }.to_json
end

delete '/tables/:table_name/truncate' do
  DB[params[:table_name].to_sym].truncate

  session[:notice] = "#{params[:table_name].to_sym.inspect} truncated!"
  redirect back
end

delete '/tables/:table_name/delete_all' do
  DB[params[:table_name].to_sym].delete

  session[:notice] = "All #{params[:table_name].to_sym.inspect} data deleted!"
  redirect back
end

delete '/tables/:table_name/drop' do
  DB.drop_table(params[:table_name].to_sym)

  session[:notice] = "Table #{params[:table_name].to_sym.inspect} dropped!"
  redirect '/'
end

put '/tables/:table_name/:id/:column_name' do
  content_type :json

  begin
    DB[params[:table_name].to_sym].where(id: params[:id]).update(params[:column_name].to_sym => params[:new_value])

    { new_value: (params[:column_name] == 'id' ? params[:new_value] : DB[params[:table_name].to_sym].first(id: params[:id])[params[:column_name].to_sym]),
      td_id:     params[:td_id]
    }.to_json
  rescue Exception => e
    status 500
    { message: e.message }.to_json
  end
end

post '/execute_sql' do
  content_type :json

  begin
    result = DB.run params[:sql]

    { result: result }.to_json
  rescue Exception => e
    status 500
    { message: e.message }.to_json
  end
end

get '/belongs_to_table_find/:table_name/:id' do
  content_type :json

  begin
    DB[params[:table_name].to_sym].first(id: params[:id]).merge(table_name: ":#{params[:table_name]}", rand_id: params[:rand_id]).to_json
  rescue
    status 500
    { table_name: ":#{params[:table_name]}", rand_id: params[:rand_id], id: params[:id] }.to_json
  end
end

helpers do
  def database_name
    begin
      if /{.*}/.match(DB.inspect)
        db_hash[:database]
      else
        /.*\/(.*)">$/.match(DB.inspect)[1]
      end
    rescue Exception => e
      puts e.message
    end
  end

  def database_adapter
    adapter_hash[DB.database_type]
  end

  def database_host
    database_hash(DB)[:host]
  end

  def column_name_with_belongs_to(column_name)
    if belongs_to_table(column_name)
      "<a href='/tables/#{belongs_to_table(column_name)}'>#{column_name[0..column_name.size - 4]}</a>_id"
    else
      column_name
    end
  end

  def notice_error
    result = ''
    if session[:notice]
      result = "<div class='alert alert-success' role='alert'>#{session[:notice]}</div>"
      session[:notice] = nil
    end

    if session[:error]
      result = "<div class='alert alert-danger' role='alert'>#{session[:error]}</div>"
      session[:error] = nil
    end
    result
  end

  def show_column_text(row, column)
    if row[column].is_a?(Integer) && belongs_to_table(column)
      rand_id = rand(1000000000)
      "<li class='dropdown' style='list-style: none'>
         <a href='#' onclick='belongs_to_table_find.call(this)' data-rand-id=#{rand_id} data-url='/belongs_to_table_find/#{belongs_to_table(column)}/#{row[column]}' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-expanded='false' title='Click to show relation data'>
           #{row[column]}
         </a>
         <ul id='ul_belongs_to_#{rand_id}' class='dropdown-menu' role='menu'>Searching...</ul>
       </li>"
    else
      row[column].is_a?(String) ? long_string_become_short(row[column]) : column_text(row[column])
    end
  end
  
  private

  def belongs_to_table(column_name)
    match_data = column_name.to_s.match(/(.*)_id$/)
    if match_data
      table = match_data[1]
      begin
        if DB.table_exists?("#{table}es")
          return "#{table}es"
        elsif DB.table_exists?("#{table[0..table.size - 2]}ies")
          return "#{table[0..(table.size - 2)]}ies"
        elsif DB.table_exists?("#{table}s")
          return "#{table}s"
        elsif DB.table_exists?("#{table}")
          return "#{table}"
        end
      rescue Exception => e
        puts e.message
      end
    end
    nil
  end

  def long_string_become_short(string_value)
    if string_value.to_s.size > 33
      "#{string_value[0..30]}<a href='#' onclick='show_full_content.call(this)' title='Click to show full content'>...</a>"
    else
      column_text(string_value)
    end
  end

  def column_text(value)
    if value.to_s.strip == ''
      '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'
    else
      value
    end
  end

  def adapter_hash
    { :sqlite => 'SQLite', :postgres => 'PostgreSQL', :mysql2 => 'MySQL', :oracle => 'Oracle', :sqlanywhere => 'SQL Anywhere' }
  end

  def database_hash(db)
    eval(/{.*}/.match(db.inspect)[0])
  end
end

private

def textarea_value_to_hash(textarea_value)
  hash = textarea_value.gsub(/(\r)+/, '').gsub(/(\n)+/, ',')
  hash = hash[0..hash.size - 2] if hash[hash.size - 1] == ','
  eval("{#{hash}}")
end

def connect_hash
  textarea_value_to_hash(params[:connect_hash]).merge(adapter: params[:adapter])
end

def db_hash
  eval(/{.*}/.match(DB.inspect)[0])
end