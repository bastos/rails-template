# README

This template is designed for personal use and open-source projects. It provides a quick start for Rails applications with essential features pre-configured, requiring minimal setup.

- **Database**: SQLite3 for simplicity and ease of setup
- **Defaults**:
  - Solid Cache for efficient caching
  - Solid Queue for background job processing
  - Solid Cable for real-time features
- **Frontend**:
  - Tailwind CSS for rapid, utility-first styling
  - Importmap for managing JavaScript modules
- **Authentication**: Google OAuth integration for secure user sign-in

[Learn more about Rails application templates](https://guides.rubyonrails.org/rails_application_templates.html)


## Usage
```sh
rails new <app_name> -j importmap -c tailwind -d sqlite3 -m https://raw.githubusercontent.com/bastos/rails-template/refs/heads/main/template.rb
```

## License

This project is released under the [MIT License](https://opensource.org/licenses/MIT).