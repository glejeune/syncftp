require 'net/ftp'
require 'yaml'
require 'digest/md5'
require 'tmpdir'
require 'rubygems'
require 'mime/types'

module Net
  class FTP
    def remote_exist?( file )
      ls( file ).size != 0
    end
  end
end

class File
  def self.binary?( file )
    MIME::Types.type_for( file ).map{ |e| (e.binary?) ? e : nil }.compact.size > 0
  end
end

class SyncFTP
  attr_reader :host, :port, :username, :password
  
  #
  # Create a new SyncFTP object for +host+
  #
  # you can specify :
  #
  #  :username - default = "anonymous"
  #  :password - default = nil
  #  :port - default = 21
  #
  def initialize(host, options = {})
    options = {:username => "anonymous", :password => nil}.merge(options)
    @host, @port = host, options[:port]||21
    @username, @password = options[:username], options[:password]
    @remote_md5s = {} 
    @local_md5s = {}
  end
  
  #
  # Sync local to remote
  #
  def sync( options = {} )
    options = { :local => ".", :remote => "." }.merge( options )
    local, remote = options[:local], options[:remote]
    
    tmpname = tmpfilename
    connect do |ftp|
      # Read remote .syncftp
      begin
        ftp.gettextfile( remote+"/"+".syncftp", tmpname )
        @remote_md5s = YAML.load( File.open( tmpname ).read )
      rescue Net::FTPPermError => e
        raise Net::FTPPermError, e.message, caller if ftp.remote_exist?( remote+"/"+".syncftp" )
      end
      
      # Do the job Bob !
      send_dir( ftp, local, remote )
      
      # Write new .syncftp
      File.open( tmpname, 'w' ) do |out|
        YAML.dump( @local_md5s, out )
      end
      ftp.puttextfile( tmpname, remote+"/"+".syncftp" )
    end
    File.delete( tmpname )
  end
  
  private
  def tmpfilename
    tmpdir = Dir::tmpdir
    basename = File.basename( $0 )
    tempname = nil
    n = 0
    
    if $SAFE > 0 and tmpdir.tainted?
      tmpdir = '/tmp'
    end
    
    begin
      t = Time.now.strftime("%Y%m%d")
      tmpfile = "#{basename}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}-#{n}"
      n += 1
      tmpname = File.join(tmpdir, tmpfile)
    end while File.exist?(tmpname)
    
    return tmpname
  end
  
  def connect
    ftp = Net::FTP.new( )
    ftp.connect( @host, @port )
    ftp.login( @username, @password )
    yield ftp
    ftp.close
  end
  
  def send_dir(ftp, local, remote)
    begin
      ftp.mkdir(remote)
    rescue Net::FTPPermError => e
      raise Net::FTPPermError, e.message, caller unless ftp.remote_exist?(remote)
    end
    
    Dir.foreach(local) do |file|
      next if file == "." or file == ".."
      
      local_file = File.join( local, file )
      remote_file = remote + "/" + file
      
      if File.stat(local_file).directory?
        # It is a directory, we recursively send it
        send_dir(ftp, local_file, remote_file)
      else
        @local_md5s[remote_file] = Digest::MD5.hexdigest( File.open(local_file).read )

        if( @local_md5s[remote_file] != @remote_md5s[remote_file] )
          # puts "-- copy #{local_file} => #{remote_file}"
          
          # It's a file, we just send it
          if File.binary?(local_file)
            ftp.putbinaryfile(local_file, remote_file)
          else
            ftp.puttextfile(local_file, remote_file)
          end
        end
      end
    end
  end
end

x = SyncFTP.new( "localhost", :username => "greg", :password => "mcag71139" )
x.sync( :local => "/Users/greg/temp/rest", :remote => "temp/rest2" )