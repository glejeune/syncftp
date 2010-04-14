require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'fakefs/safe'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'syncftp'

class Test::Unit::TestCase
end
