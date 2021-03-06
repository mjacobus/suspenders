module Suspenders
  class AppBuilder < Rails::AppBuilder
    include Suspenders::Actions

    def readme
      template 'README.md.erb', 'README.md'
      template 'MIT-LICENSE.erb', 'MIT-LICENSE.md'
    end

    def raise_on_delivery_errors
      replace_in_file 'config/environments/development.rb',
        'raise_delivery_errors = false', 'raise_delivery_errors = true'
    end

    def raise_on_unpermitted_parameters
      action_on_unpermitted_parameters = <<-RUBY

  # Raise an ActionController::UnpermittedParameters exception when
  # a parameter is not explcitly permitted but is passed anyway.
  config.action_controller.action_on_unpermitted_parameters = :raise
      RUBY
      inject_into_file(
        "config/environments/development.rb",
        action_on_unpermitted_parameters,
        before: "\nend"
      )
    end

    def configure_generators
      config = <<-RUBY
    config.generators do |generate|
      generate.decorator false
      generate.helper false
      generate.javascript_engine false
      generate.request_specs false
      generate.routing_specs true
      generate.stylesheets false
      generate.test_framework :rspec
      generate.view_specs false
      generate.fixture_replacement :machinist
    end

      RUBY

      inject_into_class 'config/application.rb', 'Application', config
    end

    def generate_devise
      generate 'devise:install'

      config = <<CODE

  if ENV['GITHUB_KEY']
    config.omniauth :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'],
      scope: 'email,public_repo'
  end

  if ENV['TWITTER_KEY']
    config.omniauth :twitter, ENV['TWITTER_KEY'], ENV['TWITTER_SECRET'],
      scope: 'email'
  end

  if ENV['FACEBOOK_KEY']
    config.omniauth :facebook, ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'],
      scope: 'email'
  end

  if ENV['GOOGLE_KEY']
    config.omniauth :google_oauth2, ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'],
      scope: 'email', strategy_class: OmniAuth::Strategies::GoogleOAuth2
  end
CODE

      inject_into_file 'config/initializers/devise.rb', config, before: "\nend"

      create_oauth_config(:development)
      create_oauth_config(:test)
      create_oauth_config(:staging)
      create_oauth_config(:production)
    end

    def create_oauth_config(env)
      application(nil, env: env) do
        <<CODE
        ENV['FACEBOOK_KEY']    = 'fake'
        ENV['FACEBOOK_SECRET'] = 'fake'
        ENV['GOOGLE_KEY']      = 'fake'
        ENV['GOOGLE_SECRET']   = 'fake'
        ENV['GITHUB_KEY']      = 'fake'
        ENV['GITHUB_SECRET']   = 'fake'
CODE
      end
    end

    def setup_user_auth
      %w(
        db/migrate/20140522135601_devise_create_users.rb
        db/migrate/20140522142949_add_name_to_users.rb
        app/views/application/_login_button.html.erb
        app/views/application/_login_status.html.erb
        app/views/application/_login_links.html.erb
        app/controllers/omniauth_callbacks_controller.rb
        spec/controllers/omniauth_callbacks_controller_spec.rb
        app/models/user.rb
        spec/models/user_spec.rb
      ).each do |file|
        copy_file file, file, force: true
      end

      %w(
        app/models/oauth
        spec/models/oauth
        spec/support
      ).each do |dir|
        directory dir
      end

      omniauth_routes = <<CODE

  devise_for :users, controllers: {
    omniauth_callbacks: "omniauth_callbacks"
  }

  devise_scope :user do
    get 'sign_in', to: 'devise/sessions#new', as: :new_user_session
    get 'sign_out', to: 'devise/sessions#destroy', as: :destroy_user_session
  end
CODE
      route omniauth_routes
    end

    def generate_machinist
      generate 'machinist:install'
    end

    def generate_foundation
      generate 'foundation:install -s'
    end

    def setup_smtp
      copy_file 'smtp.yml.erb', 'config/smtp.yml'
      copy_file 'smtp_initializer.rb', 'config/initializers/smtp_setup.rb'
    end

    def enable_rack_deflater
      config = <<-RUBY

  # Enable deflate / gzip compression of controller-generated responses
  config.middleware.use Rack::Deflater
      RUBY

      inject_into_file 'config/environments/production.rb', config,
        :after => "config.serve_static_assets = false\n"
    end

    def setup_staging_environment
      staging_file = 'config/environments/staging.rb'
      copy_file 'staging.rb', staging_file

      config = <<-RUBY

#{app_name.classify}::Application.configure do
  # ...
end
      RUBY

      append_file staging_file, config
    end

    def setup_secret_token
      template 'secret_token.rb',
        'config/initializers/secret_token.rb',
        :force => true

      say "Gerating token for testing env"
      generate_secret_token('test')

      say "Gerating token for development env"
      generate_secret_token('development')
    end

    def generate_secret_token(env)
      token = SecureRandom.urlsafe_base64(64)

      application(nil, env: env) do
        "ENV['SECRET_KEY_BASE'] = '#{token}'"
      end
    end

    def generate_home_page
      copy_file 'home.html.erb', 'app/views/pages/home.html.erb'
      copy_file 'home_routing_spec.rb', 'spec/routing/home_routing_spec.rb'
      route "root to: 'high_voltage/pages#show', id: 'home'"
    end

    def create_partials_directory
      empty_directory 'app/views/application'
    end

    def create_shared_flashes
      copy_file '_flashes.html.erb', 'app/views/application/_flashes.html.erb'
    end

    def create_shared_javascripts
      copy_file '_javascript.html.erb', 'app/views/application/_javascript.html.erb'
    end

    def create_application_layout
      template 'suspenders_layout.html.erb.erb',
        'app/views/layouts/application.html.erb',
        force: true
    end

    def remove_turbolinks
      replace_in_file 'app/assets/javascripts/application.js',
        /\/\/= require turbolinks\n/,
        ''
    end

    def replace_gemfile
      remove_file 'Gemfile'
      template 'Gemfile.erb', 'Gemfile'
    end

    def set_ruby_to_version_being_used
      template 'ruby-version.erb', '.ruby-version'
    end

    def enable_database_cleaner
      copy_file 'database_cleaner_rspec.rb', 'spec/support/database_cleaner.rb'
    end

    def configure_spec_support_features
      empty_directory_with_keep_file 'spec/features'
      empty_directory_with_keep_file 'spec/support/features'
    end

    def configure_rspec
      remove_file 'spec/spec_helper.rb'
      copy_file 'spec_helper.rb', 'spec/spec_helper.rb'
    end

    def configure_travis
      template 'travis.yml.erb', '.travis.yml'
    end

    def configure_coveralls
      template 'coveralls.yml', '.coveralls.yml'
    end

    def configure_i18n_in_specs
      copy_file 'i18n.rb', 'spec/support/i18n.rb'
    end

    def use_spring_binstubs
      run 'bundle exec spring binstub --all'
    end

    def configure_time_zone
      config = <<-RUBY
    config.active_record.default_timezone = :utc

      RUBY
      inject_into_class 'config/application.rb', 'Application', config
    end

    def configure_time_formats
      remove_file 'config/locales/en.yml'
      copy_file 'config_locales_en.yml', 'config/locales/en.yml'
    end

    def configure_action_mailer
      action_mailer_host 'development', "#{app_name}.local"
      action_mailer_host 'test', 'www.example.com'
      action_mailer_host 'staging', "staging.#{app_name}.com"
      action_mailer_host 'production', "#{app_name}.com"
    end

    def fix_i18n_deprecation_warning
      config = <<-RUBY
    config.i18n.enforce_available_locales = true

      RUBY
      inject_into_class 'config/application.rb', 'Application', config
    end

    def set_i18n
      copy_file 'devise.en.yml', 'config/locales/devise.en.yml', force: true
      copy_file 'devise.pt-BR.yml', 'config/locales/devise.pt-BR.yml'
      copy_file 'pt-BR.yml', 'config/locales/pt-BR.yml'
      copy_file 'system.pt-BR.yml', 'config/locales/system.pt-BR.yml'

      config = <<-RUBY
    config.i18n.default_locale = 'pt-BR'

      RUBY

      inject_into_class 'config/application.rb', 'Application', config
    end

    def generate_rspec
      generate 'rspec:install'
    end

    def configure_unicorn
      copy_file 'unicorn.rb', 'config/unicorn.rb'
    end

    def setup_stylesheets
      remove_file 'app/assets/stylesheets/application.css'
      copy_file 'application.css.scss',
        'app/assets/stylesheets/application.css.scss'
    end

    def gitignore_files
      remove_file '.gitignore'
      copy_file 'suspenders_gitignore', '.gitignore'
      [
        'spec/lib',
        'spec/controllers',
        'spec/helpers',
        'spec/support/matchers',
        'spec/support/mixins',
        'spec/support/shared_examples'
      ].each do |dir|
        run "mkdir #{dir}"
        run "touch #{dir}/.keep"
      end
    end

    def init_git
      git :init
      # git add: '.'
      # git commit: '-m "initial commit"'
    end

    def copy_miscellaneous_files
      copy_file 'errors.rb', 'config/initializers/errors.rb'
    end

    def customize_error_pages
      meta_tags =<<-EOS
  <meta charset='utf-8' />
  <meta name='ROBOTS' content='NOODP' />
      EOS

      %w(500 404 422).each do |page|
        inject_into_file "public/#{page}.html", meta_tags, :after => "<head>\n"
        replace_in_file "public/#{page}.html", /<!--.+-->\n/, ''
      end
    end

    def remove_routes_comment_lines
      replace_in_file 'config/routes.rb',
        /application\.routes\.draw do.*end/m,
        "application.routes.draw do\nend"
    end

    def disable_xml_params
      copy_file 'disable_xml_params.rb', 'config/initializers/disable_xml_params.rb'
    end

    def setup_default_rake_task
      append_file 'Rakefile' do
        "task(:default).clear\ntask :default => [:spec]\n"
      end
    end

    def create_database
      bundle_command 'exec rake db:create db:migrate'
    end

    private

    def override_path_for_tests
      if ENV['TESTING']
        support_bin = File.expand_path(File.join('..', '..', 'spec', 'fakes', 'bin'))
        "PATH=#{support_bin}:$PATH"
      end
    end

    def factories_spec_rake_task
      IO.read find_in_source_paths('factories_spec_rake_task.rb')
    end

    def generate_secret
      SecureRandom.hex(64)
    end
  end
end
