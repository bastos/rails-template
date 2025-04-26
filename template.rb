gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "letter_opener", group: :development

# Ask the user if they want to use PostgreSQL
use_postgres = yes?("Use PostgreSQL instead of the default SQLite? (y/N)")

if use_postgres
  say "Configuring for PostgreSQL...", :green

  # Add pg gem
  gem 'pg', '~> 1.1' # From Rails 7.1 defaults, adjust if needed

  # Remove sqlite3 gem line (will be added by default if not specified in `rails new`)
  # This ensures it's removed even if the user didn't use --database=postgresql initially
  gsub_file 'Gemfile', /^gem\s+["']sqlite3["'].*$/, ''

  # Remove existing database.yml if it exists
  remove_file 'config/database.yml'

  # Create new database.yml for Postgres using the app_name variable available in the template context
  create_file 'config/database.yml' do <<~YAML
    # PostgreSQL. Versions 9.3 and up are supported.
    #
    # Install the pg driver:
    #   gem install pg
    # On macOS with Homebrew:
    #   gem install pg -- --with-pg-config=/usr/local/bin/pg_config
    # On Windows:
    #   gem install pg
    #       Choose the win32 build.
    #       Install PostgreSQL and put its /bin directory on your path.
    #
    # Configure Using Gemfile
    # gem "pg"
    #
    default: &default
      adapter: postgresql
      encoding: unicode
      # For details on connection pooling, see Rails configuration guide
      # https://guides.rubyonrails.org/configuring.html#database-pooling
      pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

    development:
      <<: *default
      database: #{app_name}_development
      # The specified database role being used to connect to postgres.
      # To create additional roles in postgres see `$ createuser --help`.
      # When running `$ rails db:setup`, the development database will be created.
      # Examples:
      #
      #   domain: '/var/run/postgresql'
      #   host: localhost
      #   port: 5432
      #   username: #{app_name}
      #   password: ''

    test:
      <<: *default
      database: #{app_name}_test

    # As with config/credentials.yml, you never want to store sensitive information,
    # like your database password, in your source code. If your source code is
    # ever seen by anyone, they now have access to your database.
    #
    # Instead, provide the password or database URL as an environment variable when you
    # deploy your application. For example:
    #
    #   DATABASE_URL="postgres://myuser:mypass@localhost/somedatabase"
    #
    # If the connection URL is provided in the special DATABASE_URL environment
    # variable, Rails will automatically merge its configuration values on top of
    # the values provided in this file. Alternatively, you can specify a connection
    # URL environment variable explicitly:
    #
    #   production:
    #     url: <%= ENV["MY_APP_DATABASE_URL"] %>
    #
    production:
      <<: *default
      database: #{app_name}_production
      username: #{app_name}
      password: <%= ENV["#{app_name.upcase}_DATABASE_PASSWORD"] %>
    YAML
  end
else
  # Explicitly add sqlite3 gem if not using Postgres, in case it was removed by mistake or skipped
  # This makes the default choice more robust.
  gem 'sqlite3', '~> 1.4'
  say "Using default SQLite.", :yellow
end

after_bundle do
  git add: "."

  git commit: "-m 'chore: initial commit'"

  generate :model, "User",
    "name:string",
    "email:string:index",
    "authentication_provider:string:index",
    "authentication_uid:string:index"

  environment "config.action_mailer.delivery_method = :letter_opener", env: "development"

  environment "config.action_mailer.perform_deliveries = true", env: "development"

  insert_into_file "app/models/user.rb", after: "class User < ApplicationRecord\n" do <<~RUBY.indent(2)
      validates :authentication_provider, presence: true
      validates :authentication_uid, presence: true
      validates :email, presence: true

      def self.from_omniauth(auth)
        where(authentication_uid: auth.uid, authentication_provider: auth.provider).first_or_initialize do |user|
          user.email = auth.info.email
          user.name = auth.info.name
        end
      end
    RUBY
  end

  insert_into_file "app/controllers/application_controller.rb",
      after: "class ApplicationController < ActionController::Base\n" do <<~RUBY.indent(2)
      helper_method :current_user, :user_signed_in?

      def current_user
        @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
      end

      def user_signed_in?
        !!current_user
      end
    RUBY
  end

  generate :controller, "Sessions", "--skip-routes", "--skip-helper"

  insert_into_file "app/controllers/sessions_controller.rb", after: "SessionsController < ApplicationController\n" do <<~RUBY.indent(2)
      def create
        user = User.from_omniauth(request.env["omniauth.auth"])
        if user.save
          session[:user_id] = user.id
          redirect_to root_path, notice: "Signed in successfully"
        else
          redirect_to root_path, alert: "Failed to sign in"
        end
      end

      def destroy
        session[:user_id] = nil
        redirect_to root_path, notice: "Signed out successfully"
      end
    RUBY
  end

  generate :controller, "Home"

  insert_into_file "app/controllers/home_controller.rb", after: "class HomeController < ApplicationController\n" do <<~RUBY.indent(2)
      def index
      end
    RUBY
  end

  create_file "app/views/home/index.html.erb", <<~HTML.indent(4)
    <h1>Welcome to the home page</h1>
  HTML

  route <<~RUBY.indent(2)
    get "auth/:provider/callback", to: "sessions#create"
    get "auth/failure", to: redirect("/")
    post "signout", to: "sessions#destroy", as: "signout"
    root "home#index"
  RUBY

  initializer "omniauth.rb", <<~RUBY
    Rails.application.config.middleware.use OmniAuth::Builder do
      if Rails.env.production?
        provider :google_oauth2, Rails.application.credentials.google.oauth2.client_id!, Rails.application.credentials.google.oauth2.client_secret!
      else
        # Change this to your Google OAuth client ID and secret as above or using environment variables
        provider :developer
      end
    end

    OmniAuth.config.allowed_request_methods = [ :post ]
    OmniAuth.config.full_host = Rails.env.production? ? "https://example.com" : "http://127.0.0.1:3000"
  RUBY

  insert_into_file "app/views/layouts/application.html.erb", after: "<body>\n" do <<~HTML.indent(4)
    <header>
      <% if user_signed_in? %>
        <%= button_to "Sign out", signout_path, method: :post, data: { turbo: false } %>
      <% else %>
        <% if Rails.env.development? %>
          <%= button_to "Sign in", '/auth/developer', method: :post, data: { turbo: false } %>
        <% else %>
          <%= button_to "Sign in", '/auth/google_oauth2', method: :post, data: { turbo: false } %>
        <% end %>
      <% end %>
    </header>
    HTML
  end

  rails_command "db:drop db:create db:migrate"

  run "bundle exec rubocop -a"

  git add: "."

  git commit: "-m 'feat: scaffold application'"
end
