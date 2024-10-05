gem "dotenv-rails"
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "letter_opener", group: :development
gem "webmock", group: :test
gem "mocha", group: :test

after_bundle do
  git add: "."

  git commit: "-m 'chore: initial commit'"

  generate :model, "User",
    "name:string",
    "email:string:index",
    "authentication_provider:string:index",
    "authentication_uid:string:index"

  rails_command "solid_cache:install"

  rails_command "solid_queue:install"

  rails_command "solid_cable:install"

  environment "config.action_mailer.delivery_method = :letter_opener", env: "development"

  environment "config.action_mailer.perform_deliveries = true", env: "development"

  insert_into_file "config/database.yml", after: "production:\n" do <<~YAML.indent(2)
      primary:
        <<: *default
        database: storage/production.sqlite3
      cache:
        <<: *default
        database: storage/production_cache.sqlite3
        migrations_paths: db/cache_migrate
      queue:
        <<: *default
        database: storage/production_queue.sqlite3
        migrations_paths: db/queue_migrate
      cable:
        <<: *default
        database: storage/production_cable.sqlite3
        migrations_paths: db/cable_migrate
    YAML
  end

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
