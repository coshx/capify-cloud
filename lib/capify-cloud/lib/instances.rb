class Instances

  def initialize(connection)
    @connection = connection
  end

  def find_by_ip(ip)
    @connection.servers.select {|instance| instance.public_ip_address.to_s == ip.to_s}.first
  end

  def find_prototype_by_role_and_stage(role, stage)
    stage_instances =  @connection.servers.select {|instance| instance.tags["Stage"] == stage}
    stage_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}.first
  end

  def find_web_on_current_stage(stage)
    stage_instances =  @connection.servers.select {|instance| instance.tags["Stage"] == stage}
    stage_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?('web') rescue false}
  end

  def print_prototypes
    prototype_instances = @connection.servers.select {|instance| instance.tags["Options"] == 'prototype'}
    prototype_instances.each do |instance|
      puts "#{instance.id} #{instance.tags['Name']}"
    end
  end

  def all
    return @connection.servers
  end

end