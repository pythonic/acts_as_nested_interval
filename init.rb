Dir[File.dirname(__FILE__) + "/lib/**/*.rb"].each do |feature|
  require feature if feature !~ /\/(?!abstract)[^\/]+_adapter.rb$/
end
