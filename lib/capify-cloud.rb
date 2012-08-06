require 'rubygems'
require 'fog'
require 'colored'
require File.expand_path(File.dirname(__FILE__) + '/capify-cloud/server')

class CapifyCloud
  attr_accessor :load_balancer, :instances
  SLEEP_COUNT = 5
  
  def initialize(cloud_config = "config/cloud.yml")
    case cloud_config
    when Hash
      @cloud_config = cloud_config
    when String
      @cloud_config = YAML.load_file cloud_config
    else
      raise ArgumentError, "Invalid cloud_config: #{cloud_config.inspect}"
    end
    @cloud_providers = @cloud_config[:cloud_providers]
    @instances = []
    @cloud_providers.each do |cloud_provider|
      config = @cloud_config[cloud_provider.to_sym]
      case cloud_provider
      when 'Brightbox'
        servers = Fog::Compute.new(:provider => cloud_provider, :brightbox_client_id => config[:brightbox_client_id],
          :brightbox_secret => config[:brightbox_secret]).servers
        servers.each do |server|
          @instances << server if server.ready?
        end
        else
        regions = determine_regions(cloud_provider)
        regions.each do |region|
          servers = Fog::Compute.new(:provider => cloud_provider, :aws_access_key_id => config[:aws_access_key_id],
            :aws_secret_access_key => config[:aws_secret_access_key], :region => region).servers
          servers.each do |server|
            @instances << server if server.ready?
          end
        end
      end
    end
  end

  def compute
    config = @cloud_config[:AWS]
    @compute ||= Fog::Compute.new(:provider => :AWS, :aws_access_key_id => config[:aws_access_key_id],:aws_secret_access_key => config[:aws_secret_access_key], :region => config[:params][:region])
  end

  def auto_scale
    config = @cloud_config[:AWS]
    @autoscale ||=Fog::AWS::AutoScaling.new(:aws_access_key_id => config[:aws_access_key_id],:aws_secret_access_key => config[:aws_secret_access_key])
  end

  def elb
    config = @cloud_config[:AWS]
    @elb ||= Fog::AWS::ELB.new(:aws_access_key_id => config[:aws_access_key_id], :aws_secret_access_key => config[:aws_secret_access_key], :region => config[:params][:region])
  end

  def get_load_balancers
    elb.load_balancers.all
  end

  def get_load_balancer_by_instance(instance_id)
    hash = elb.load_balancers.inject({}) do |collect, load_balancer|
      load_balancer.instances.each {|load_balancer_instance_id| collect[load_balancer_instance_id] = load_balancer}
      collect
    end
    hash[instance_id]
  end

  def get_load_balancer_by_name(load_balancer_name)
    lbs = {}
    elb.load_balancers.each do |load_balancer|
      lbs[load_balancer.id] = load_balancer
    end
      lbs[load_balancer_name]
  end

  def instance_health(load_balancer, instance)
    elb.describe_instance_health(load_balancer.id, instance.id).body['DescribeInstanceHealthResult']['InstanceStates'][0]['State']
  end

  def deregister_instance_from_elb(instance_name)
    return unless @cloud_config[:load_balanced]
    instance = get_instance_by_name(instance_name)
    return if instance.nil?
    @@load_balancer = get_load_balancer_by_instance(instance.id)
    return if @@load_balancer.nil?

    elb.deregister_instances_from_load_balancer(instance.id, @@load_balancer.id)
  end

  def register_instance_in_elb(instance_name, load_balancer_name = '')
    return if !@cloud_config[:load_balanced]
    instance = get_instance_by_name(instance_name)
    return if instance.nil?
    load_balancer =  get_load_balancer_by_name(load_balancer_name) || @@load_balancer
    return if load_balancer.nil?

    elb.register_instances_with_load_balancer(instance.id, load_balancer.id)

    fail_after = @cloud_config[:fail_after] || 30
    state = instance_health(load_balancer, instance)
    time_elapsed = 0

    while time_elapsed < fail_after
      break if state == "InService"
      sleep SLEEP_COUNT
      time_elapsed += SLEEP_COUNT
      STDERR.puts 'Verifying Instance Health'
      state = instance_health(load_balancer, instance)
    end
    if state == 'InService'
      STDERR.puts "#{instance.name}: Healthy"
    else
      STDERR.puts "#{instance.name}: tests timed out after #{time_elapsed} seconds."
    end
  end


  def find_latest_ami(role)
      images = Array.new
      project_ami.body['imagesSet'].each do |image|
        unless image["tagSet"].empty?
          images.push(image) if image["tagSet"]["Roles"].include? role
        end
      end
      images = images.sort{|image1,image2| Time.parse(image2["tagSet"]["Version"]).to_i <=> Time.parse(image1["tagSet"]["Version"]).to_i}
      images[0]["imageId"]
  end

  def latest_ami(role)
    @latest_ami ||= find_latest_ami(role)
  end

  def image_state(ami)
    compute.describe_images('image-id' => ami.body['imageId']).body['imagesSet'].first['imageState']
  end

  def image_tags(ami_id)
    compute.describe_images('image-id' => ami_id).body['imagesSet'].first["tagSet"]
  end

  def create_ami_image(instance, role)
      ami = compute.create_image(instance.id,"#{role}-#{Time.now.utc.iso8601.gsub(':','.')}", "#{role}-#{Time.now.utc.iso8601.gsub(':','.')}")
      progress_output = "."
      Fog.wait_for do
        STDOUT.write "\r#{progress_output}"
        progress_output = progress_output+"."
        image_state(ami) != 'pending'
      end
      ami
    end

  def create_ami(role)
    unless @cloud_providers.include?('AWS')
      puts "cloud:create_ami supports AWS only."
      return
    end
    instances = get_instances_by_role(role)
    instances.each do |instance|
        ami = create_ami_image(instance,role)
        if image_state(ami) == 'available'
          compute.create_tags(ami.body['imageId'], instance.tags)
          if image_tags(ami.body['imageId']).empty?
            puts "\nami created, but there was an error adding it's tags - please try creating a new ami in a few minutes"
          else
            puts "\n#{ami.body['imageId']} created from #{instance.id} #{image_tags(ami.body['imageId'])}"
          end
          return ami
        else
          puts "\nami create failed"
          return nil
        end
    end
  end

  def project_ami
    compute.describe_images('tag:Project' => @cloud_config[:project_tag])
  end

  def autoscale_create(role)
    region = @cloud_config[:AWS][:params][:region]
    instance_type = @cloud_config[:AWS][:params][:instance_type]
    begin auto_scale.create_launch_configuration(latest_ami(role),instance_type, role+'_launch_configuration_'+latest_ami(role))                             ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.create_auto_scaling_group(role+'_group', region, role+'_launch_configuration_'+latest_ami(role), max = 500, min = 2, {}) ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.put_scaling_policy('ChangeInCapacity', role+'_group', 'ScaleUp', scaling_adjustment = 1, {})                     ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.put_scaling_policy('ChangeInCapacity', role+'_group', 'ScaleDown', scaling_adjustment = -1, {})                  ; rescue StandardError => e ;  puts e ; end
  end

  def autoscale_update(role)
    instance_type = @cloud_config[:AWS][:params][:instance_type]
    begin auto_scale.create_launch_configuration(latest_ami(role),instance_type, role+'_launch_configuration_'+latest_ami(role))                      ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.update_auto_scaling_group(role+'_group', "LaunchConfigurationName" => role+'_launch_configuration_'+latest_ami(role) )  ; rescue StandardError => e ;  puts e ; end
  end

  def display_instances
    desired_instances.each_with_index do |instance, i|
      puts sprintf "%02d:  %-40s  %-20s %-20s  %-20s  %-25s  %-20s  (%s)  (%s)",
        i, (instance.name || "").green, instance.provider.yellow, instance.id.red, instance.flavor_id.cyan,
        instance.contact_point.blue, instance.zone_id.magenta, (instance.tags["Roles"] || "").yellow,
        (instance.tags["Options"] || "").yellow
      end
  end

  def server_names
    desired_instances.map {|instance| instance.name}
  end

  def project_instances
    @instances.select {|instance| instance.tags["Project"] == @cloud_config[:project_tag]}
  end

  def desired_instances
    @cloud_config[:project_tag].nil? ? @instances : project_instances
  end

  def get_instances_by_role(role)
    desired_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}
  end

  def get_instances_by_region(roles, region)
    return unless region
    desired_instances.select {|instance| instance.availability_zone.match(region) && instance.roles == roles.to_s rescue false}
  end

  def get_instance_by_name(name)
    desired_instances.select {|instance| instance.name == name}.first
  end

  def determine_regions(cloud_provider = 'AWS')
    @cloud_config[cloud_provider.to_sym][:params][:regions] || [@cloud_config[cloud_provider.to_sym][:params][:region]]
  end

end

