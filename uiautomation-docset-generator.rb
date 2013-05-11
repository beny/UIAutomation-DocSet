#!/usr/bin/ruby
require 'net/http'
require 'sqlite3'
require 'FileUtils'

SERVER = "developer.apple.com"
ROOT = "/library/ios/documentation/DeveloperTools/Reference/UIAutomationRef/"
IDENTIFIER = "uiautomation"
BUNDLE_NAME = "UIAutomation"
PLATFORM_FAMILY = "ios"
VERSION = 0.1
DATA_URL = "https://raw.github.com/beny/UIAutomation-DocSet/master/UIAutomation.tgz"

def remove_javascript(html)
  puts "\tRemoving javascript ..."
  html.gsub(/<script>(.*?)<\/script>/m, "")
end

def download_stylesheets(html, path)
  puts "\tDownloading stylesheets ... "
  css_links = html.scan(/text\/css"\shref=\"(.*\.css)\"/)
  css_links = css_links.to_a.map{|x| x.first}
  css_links.each do |link|
    css_filename = link.split("/").last
    css_data = Net::HTTP.get(SERVER, "#{ROOT}#{link}")
    File.open("#{path}#{css_filename}", "w") do |file|
      file.write(css_data)
    end
  end
end
  
def fix_stylesheets(html)
  puts "\tFixing stylesheets ... "
  html = html.gsub(/(text\/css"\shref=\")(.*\/)(.*\.css")/, '\1\3')
  html.delete("")
end

# remove previous docset
system("rm -fr #{BUNDLE_NAME}.docset #{BUNDLE_NAME}.xml #{BUNDLE_NAME}.tgz")

# create docset directory structure
Dir.mkdir("#{BUNDLE_NAME}.docset")
Dir.mkdir("#{BUNDLE_NAME}.docset/Contents")
Dir.mkdir("#{BUNDLE_NAME}.docset/Contents/Resources")
Dir.mkdir("#{BUNDLE_NAME}.docset/Contents/Resources/Documents/")

puts "Working with \"index\" file"
index_html = Net::HTTP.get(SERVER, "#{ROOT}_index.html")

# remove javascript
index_html = remove_javascript(index_html)

# download and fix stylesheets
download_stylesheets(index_html, "#{BUNDLE_NAME}.docset/Contents/Resources/Documents/")
index_html = fix_stylesheets(index_html)

puts "\tFixing main links ... "
# find and replace classes links
classes_html = index_html.match(/Class References<\/div>(.*?)<\/ol><\/div>/m)[1]
classes_html = classes_html.gsub(/^\s*\n/,"")
classes = Array.new
classes_html.split("\n").each do |line|
  line = line.strip
  if !line.empty?
    link = line.match(/href=\"(.*?)\"/)[1]
    name = line.match(/\">[^<](.*?)</)[1].strip
    
    index_html = index_html.sub(link, "#{name}.html")
    classes << {:name => name, :link => link}
  end
end

# save index file
File.open("#{BUNDLE_NAME}.docset/Contents/Resources/Documents/index.html", "w") do |file|
  file.write(index_html)
end

# download all classes files
all_methods = Array.new
classes.each do |cls|
  puts "Working with \"#{cls[:name]}\" files"
  class_html = Net::HTTP.get(SERVER, "#{ROOT}#{cls[:link]}")

  class_html = remove_javascript(class_html)
  class_html = fix_stylesheets(class_html)
  
  # methods = class_html.scan(/api\smethod.*(\/\/apple_ref\/doc\/uid.*?)\"\stitle=\"(.*?)\"/
  methods = class_html.scan(/jump\smethod\">(.*?)</).to_a.map{|x| x.first}
  all_methods << {:name => cls[:name], :methods => methods, :link => cls[:link]}

  File.open("#{BUNDLE_NAME}.docset/Contents/Resources/Documents/#{cls[:name]}.html", "w") do |file|
    file.write(class_html)
  end
end

# create sqlite
db = SQLite3::Database.new("#{BUNDLE_NAME}.docset/Contents/Resources/docSet.dsidx")
rows = db.execute <<-SQL
  CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
  CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
SQL

# fill data into sqlite
all_methods.each do |cls|
  # insert class
  db.execute "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{cls[:name]}', 'Class', '#{cls[:name]}.html');"
  
  # insert methods
  cls[:methods].each do |method_name|
    db.execute "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{method_name}', 'Method', '#{cls[:name]}.html');"
  end
end

# create plist
plist = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>#{IDENTIFIER}</string>
	<key>CFBundleName</key>
	<string>#{BUNDLE_NAME}</string>
	<key>DocSetPlatformFamily</key>
	<string>#{PLATFORM_FAMILY}</string>
	<key>isDashDocset</key>
	<true/>
</dict>
</plist>
PLIST

File.open("#{BUNDLE_NAME}.docset/Contents/Info.plist", "w") do |file|
  file.write(plist)
end

# write feed xml
feed_xml = <<-XML
<?xml version="1.0"?>
<entry>
	<version>#{VERSION}</version>
	<url>#{DATA_URL}</url>
</entry>
XML

File.open("UIAutomation.xml", "w") do |file|
  file.write(feed_xml)
end

# tar docset
system("tar --exclude='.DS_Store' -cvzf #{BUNDLE_NAME}.tgz #{BUNDLE_NAME}.docset")