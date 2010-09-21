# Copyright (c) 2009 Gregoire Lejeune
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
require 'net/ftp'
require 'yaml'
require 'digest/md5'
require 'tmpdir'
require 'logger'
require 'rubygems'
require 'mime/types'

module Net
  class FTP
    #
    # Net::FTP extension
    #
    # Check if the +file+ exist on the remote FTP server
    #
    def remote_file_exist?( file )
      ls( file ).size != 0
    end

    #
    # Net::FTP extension
    #
    # Check if the +dir+ exist on the remote FTP server
    #
    def remote_dir_exist?( dir )
      path = dir.split( "/" )
      find = path.pop
      path = path.join( "/" )
      path = "." if path == ""
      altdir = dir
      altdir = dir[2..-1] if dir[0,2] == "./"
      
      return true if dir == "."
      
      begin
        nlst( path ).include?( find ) or nlst( path ).include?( dir ) or nlst( path ).include?( altdir )
      rescue Net::FTPTempError
        return false
      end
    end
    
    #
    # Net::FTP extension
    #
    # Like FileUtils.mkdir_p but for Net::FTP
    #
    def mkdir_p( dir )
      path = dir.split( "/" )
      mkpath = path.shift
      begin
        mkdir( mkpath ) unless mkpath == ""
      rescue Net::FTPPermError => e
        raise Net::FTPPermError, e.message, caller unless remote_dir_exist?(mkpath)
      end
      path.each do |d|
        mkpath = [mkpath, d].join( "/" )
        begin
          mkdir( mkpath )
        rescue Net::FTPPermError => e
          raise Net::FTPPermError, e.message, caller unless remote_dir_exist?(mkpath)
        end
      end
    end
  end
end

class File
  #
  # File extension
  #
  # Check if the +file+ is a binary file
  #
  def self.binary?( file )
    if MIME::Types.type_for( file ).size == 0
      return true
    end
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
  # * +:username+ - default = "anonymous"
  # * +:password+ - default = nil
  # * +:port+ - default = 21
  # * +:logfile+ - default = STDOUT
  # * +:loglevel+ - default = Logger::UNKNOWN (Cool if you don't want logs)
  #
  def initialize(host, options = {})
    options = {
      :username => "anonymous", 
      :password => nil, 
      :logfile => STDOUT, 
      :loglevel => Logger::UNKNOWN,
      :catalog => :remote
    }.merge(options)
    @host, @port = host, options[:port]||21
    @username, @password = options[:username], options[:password]
    @catalog = options[:catalog]
    @remote_md5s = {} 
    @local_md5s = {}
    @log = Logger.new( options[:logfile] )
    @log.level = options[:loglevel]
  end
  
  #
  # Sync local to remote
  #
  # you can specify :
  #
  # * +:local+ : the local directory (default = ".")
  # * +:remote+ : the remote directory (default = ".")
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
        raise Net::FTPPermError, e.message, caller if ftp.remote_file_exist?( remote+"/"+".syncftp" )
      end
      
      # Do the job Bob !
      send_dir( ftp, local, remote )
      
      # Write new .syncftp
      File.open( tmpname, 'w' ) do |out|
        YAML.dump( @local_md5s, out )
      end
      
      # Delete files
      @delete_dirs = []
      @delete_files = []
      @remote_md5s.keys.clone.delete_if{ |f| @local_md5s.keys.include?(f) }.each do |f|
        if @remote_md5s[f] == "*"
          @delete_dirs << f
        else
          @delete_files << f
        end
      end
      @delete_files.each do |f|
        @log.info "Delete ftp://#{@host}:#{@port}/#{f}"
        ftp.delete( f )
      end      
      @delete_dirs.each do |f|
        @log.info "Delete ftp://#{@host}:#{@port}/#{f}"
        ftp.delete( f )
      end      
      
      ftp.puttextfile( tmpname, remote+"/"+".syncftp" )
    end
    File.delete( tmpname )
  end
  
  def getCatalog #:nodoc
  end
  
  def saveCatalog #:nodoc
  end
  
  def catalogFileName #:nodoc
  end
  
  private
  def tmpfilename #:nodoc:
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
  
  def connect #:nodoc:
    ftp = Net::FTP.new( )
    ftp.connect( @host, @port )
    ftp.login( @username, @password )
    yield ftp
    ftp.close
  end
  
  def send_dir(ftp, local, remote) #:nodoc:
    unless ftp.remote_dir_exist?(remote)
      @log.info "Create directory ftp://#{@host}:#{@port}/#{remote}"
      ftp.mkdir_p(remote) 
    end
    
    Dir.foreach(local) do |file|
      next if file == "." or file == ".."
      
      local_file = File.join( local, file )
      remote_file = remote + "/" + file

      if File.stat(local_file).directory?
        # It is a directory, we recursively send it
        @local_md5s[remote_file] = "*"
        send_dir(ftp, local_file, remote_file)
      else
        @local_md5s[remote_file] = Digest::MD5.hexdigest( File.open(local_file).read )
        
        # Local file still exist... Copy...
        if( @local_md5s[remote_file] != @remote_md5s[remote_file] )
          # It's a file, we just send it
          if File.binary?(local_file)
            @log.info "Copy [Binary] #{local_file} to ftp://#{@host}:#{@port}/#{remote_file}"
          
            ftp.putbinaryfile(local_file, remote_file)
          else
            @log.info "Copy [Text] #{local_file} to ftp://#{@host}:#{@port}/#{remote_file}"
          
            ftp.puttextfile(local_file, remote_file)
          end
        else
          @log.info "#{local_file} don't need to be overwritten !"
        end
      end
    end
  end
end
