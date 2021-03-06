Puppet::Type.type(:bmcuser).provide(:ipmitool) do
  desc "Provides ipmitool support for the bmc type"

  commands :ipmitoolcmd => 'ipmitool'
  # if the open ipmi driver does not exist we can perform any of these configurations
  # check to see that openipmi driver is loaded and ipmi device exists
  confine :bmc_device_present => [:true, true]

  mk_resource_methods

  CHANNEL_LOOKUP = {
      'Dell Inc.'         => '1',
      'FUJITSU'           => '2',
      'FUJITSU SIEMENS'   => '2',
      'HP'                => '2',
      'Intel Corporation' => '1',
  }
  PRIV = {
      :ADMINISTRATOR => 4,
      :ADMIN => 4,
      :USER => 2,
      :CALLBACK => 1,
      :OPERATOR => 3,
      :NOACCESS => 15,
      'NO ACCESS' => 15,
  }

  # TODO: set the right channel for new user, atm they get channel 0
  # which means no web interface access
  
  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def create
    set_username resource[:username]
    userpass resource[:userpass]
    set_privlevel PRIV[resource[:privlevel]]
    set_enable id # finds an unused id
  end

  # get the user id supplied by the resource or find out the current user id
  # if a user id cannot be found, try and create a new user id by looking for empty slots
  def id
   @id ||= @property_hash[:id] || @resource[:id] || user_id(resource[:username])
  end

  def destroy
    set_username '(Empty User)'
    set_privlevel PRIV[:NOACCESS]
    set_disable id
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def set_username(value)
    ipmitoolcmd([ "user", "set", "name", id, value] )
  end

  def set_userpass(value)

  end

  def set_privlevel(value)
    ipmitoolcmd([ "user", "priv", id, value, channel ])

  end

  def set_enable(value)
    ipmitoolcmd([ "user", "enable", value ])
  end

  def set_disable(value)
    ipmitoolcmd([ "user", "disable", value ])
  end

   # get userpass
   def userpass
       args = [command(:ipmitoolcmd), "user", "test", @resource[:id], "20", @resource[:userpass]]
       output = Puppet::Util::Execution.execute(args, :failonfail => false, :combine => false)
       if output.exitstatus == 0
         true
       elsif output.exitstatus == 1
         false
       else
         self.warning _("Could not check for updates, '%{ipmitoolcmd} password test' exited with %{status}") % { cmd: command(:ipmitoolcmd), status: output.exitstatus }
       end
   end

   # set userpass
   def userpass=(value)
     case userpass
     when true
       self.warning "nothing todo"
     when false
       ipmitoolcmd([ "user", "set", "password", id, @resource[:userpass] ])
     end
   end

  def users
    unless @users
      userdata = ipmitoolcmd([ "user", "list", CHANNEL_LOOKUP.fetch(Facter.value(:dmi)['board']['manufacturer'], '1')])
      @users = []
      userdata.lines.each do | line|
        # skip the header
        next if line.match(/^ID/)
        id, name, callin, linkauth, enabled, priv = line.chomp.split(' ', 6)
        # create the resource
        users << {:name => name, :username => name, :id => id, :enabled => enabled,
                  :callin => callin, :linkauth => linkauth , :privlevel => priv}
      end
    end
    @users
  end

  def new_user_id
    begin
      user = users.find {|user| user[:name] =~ /Empty/i } || users.find {|user| !user[:enabled] }
      user[:id]
    rescue
      fail('Cannot allocate a user id, all ipmi users are taken already')
    end
  end

  def user_id(user)
    if ! found_user = users.find {|u| u[:name] == user }
      new_user_id
    else
      found_user[:id]
    end
  end

  def self.instances
    userdata = ipmitoolcmd([ "user", "list", CHANNEL_LOOKUP.fetch(Facter.value(:dmi)['board']['manufacturer'], '1')])
    users = []
    userdata.lines.each do | line|
      # skip the header
      next if line.match(/^ID/)
      next if line.match(/Empty/i)
      next if line.match(/^1/)
      id, name, callin, linkauth, enabled, priv = line.chomp.split(' ', 6)
      # create the resource
      users << new(:name => name, :username => name, :id => id, :ensure => :present,
                   :privlevel => priv)
    end
    users
  end

  def self.prefetch(resources)
    users = instances
    if users
      resources.keys.each do | name|
        if provider = users.find{|user| user.username == name }
          resources[name].provider = provider
        end
      end
    end
  end

  def channel
    CHANNEL_LOOKUP.fetch(Facter.value(:dmi)['board']['manufacturer'], '1')
  end
end
