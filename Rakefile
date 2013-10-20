require 'rake'
require 'rake/testtask'
require 'rake/task'

desc 'Run unit tests.'
task :default => 'test:unit'

namespace :test do
  desc 'Run unit test'
  Rake::TestTask.new(:unit) do |t|
    t.libs << 'app/controllers/'
    t.libs << "test"
    t.pattern = 'test/**/*_test.rb'
    t.verbose = true
  end
end
