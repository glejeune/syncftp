require 'helper'

class TestSyncftp < Test::Unit::TestCase
  context "A User story" do
    setup do
      @sync = SyncFTP.new( 'localhost', :username => 'greg', :password => 'mcag71139' )
    end
  
    should "be initialized" do
      assert_not_nil @sync
    end
  end
end
