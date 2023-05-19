source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gem 'spree_multi_vendor'

group :development, :test do
  gem 'rails-controller-testing'
  gem 'byebug'
end

gemspec
