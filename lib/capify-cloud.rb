
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
  def cloudwatch
    config = @cloud_config[:AWS]
    @cloudwatch ||= Fog::AWS::CloudWatch.new(:aws_access_key_id => config[:aws_access_key_id], :aws_secret_access_key => config[:aws_secret_access_key], :region => config[:params][:region])
  end

  def load_balancer_name
    (@cloud_config[:project_tag].gsub(/(\W|\d)/, ""))
  end

  def launch_configuration_name(role)
    (role+'_launch_configuration_'+latest_ami_id(role))
  end

  def autoscale_group_name(role)
    (role+'_group')
  end

  def latest_ami_id(role)
    @latest_ami ||= latest_ami(role)
  end

  def latest_ami(role)
    images = Array.new
    project_ami.body['imagesSet'].each do |image|
      unless image["tagSet"].empty?
        images.push(image) if image["tagSet"]["Roles"].include? role
      end
    end
    if images.any?
      images = images.sort{|image1,image2| Time.parse(image2["tagSet"]["Version"]).to_i <=> Time.parse(image1["tagSet"]["Version"]).to_i}
      images[0]["imageId"]
    else
      puts "no images with #{role} role"
    end
  end

  def image_state(ami)
    compute.describe_images('image-id' => ami.body['imageId']).body['imagesSet'].first['imageState']
  end

  def compute_state(instance)
    compute.describe_instances( 'instance-id' => instance).body['reservationSet'].first['instancesSet'].first['instanceState']['name']
  end

  def image_tags(ami)
    compute.describe_images('image-id' => ami).body['imagesSet'].first["tagSet"]
  end

  def project_ami
    compute.describe_images('tag:Project' => @cloud_config[:project_tag])
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

  def get_instance_by_name(name)
      desired_instances.select {|instance| instance.name == name}.first
  end

  def get_instances_by_role(role)
     desired_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}
  end

  def get_instances_by_region(roles, region)
    return unless region
    desired_instances.select {|instance| instance.availability_zone.match(region) && instance.roles == roles.to_s rescue false}
  end

  def determine_regions(cloud_provider = 'AWS')
    @cloud_config[cloud_provider.to_sym][:params][:regions] || [@cloud_config[cloud_provider.to_sym][:params][:region]]
  end

  def display_instances
    desired_instances.each_with_index do |instance, i|
      puts sprintf "%02d:  %-40s  %-20s %-20s  %-20s  %-25s  %-20s  (%s)  (%s)",
      i, (instance.name || "").green, instance.provider.yellow, instance.id.red, instance.flavor_id.cyan,
      instance.contact_point.blue, instance.zone_id.magenta, (instance.tags["Roles"] || "").yellow,
      (instance.tags["Options"] || "").yellow
    end
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

  def terminate_instance(instance)
    compute.terminate_instances(instance).body['instancesSet'].first
    Fog.wait_for do
      compute_state(instance) == 'terminated'
    end

  end

  def describe_cloudwatch_alarms(options = {})
    cloudwatch.describe_alarms(options)
  end

  def describe_load_balancers(options = {})
    elb.describe_load_balancers(options)
  end

  def describe_load_balancer
    begin elb.describe_load_balancers({"LoadBalancerNames" => load_balancer_name}) ; rescue StandardError => e ;  puts e ; end
  end

  def describe_auto_scaling_groups(options = {})
    auto_scale.describe_auto_scaling_groups(options)
  end

  def describe_auto_scaling_policies(options = {})
    auto_scale.describe_policies(options)
  end

  def describe_autoscale_group(role)
    begin auto_scale.describe_auto_scaling_groups('AutoScalingGroupNames' => role+'_group')  ; rescue StandardError => e ;  puts e ; end
  end

  def describe_launch_configurations
    begin auto_scale.describe_launch_configurations  ; rescue StandardError => e ;  puts e ; end
  end

  def create_load_balancer
    zone = @cloud_config[:AWS][:params][:availability_zone]
    listeners = Array.new
    listeners.push({"Protocol"=>"HTTPS", 'LoadBalancerPort' => 443, "SSLCertificateId"=>"arn:aws:iam::710121801201:server-certificate/NetworkCert", "InstancePort"=>443})
    listeners.push({"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80})
    elb.create_load_balancer(zone, load_balancer_name, listeners)
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

  def create_autoscale(role)
    instance_type = @cloud_config[:AWS][:params][:instance_type]
    zone = @cloud_config[:AWS][:params][:availability_zone]
    ami = latest_ami_id(role)
    autoscale_tags = Array.new
    image_tags(ami).each_pair do |k,v|
      if k == "Name"
        autoscale_tags.push({'key'=>k,'value'=>auto+"_"+v, 'propagate_at_launch'=> 'true'})
      else
        autoscale_tags.push({'key'=>k,'value'=>v, 'propagate_at_launch'=> 'true'})
      end
    end
    begin auto_scale.create_launch_configuration(ami,instance_type, launch_configuration_name(role))                                               ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.create_auto_scaling_group(autoscale_group_name(role), zone, launch_configuration_name(role),max = 500, min = 2, {'LoadBalancerNames'=>load_balancer_name,'DefaultCooldown'=>0, 'Tags' => autoscale_tags })   ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.put_scaling_policy('ChangeInCapacity', autoscale_group_name(role), 'ScaleUp', scaling_adjustment = 1, {})                     ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.put_scaling_policy('ChangeInCapacity', autoscale_group_name(role), 'ScaleDown', scaling_adjustment = -1, {})                  ; rescue StandardError => e ;  puts e ; end
  end

  def update_autoscale(role)
    instance_type = @cloud_config[:AWS][:params][:instance_type]
    begin auto_scale.create_launch_configuration(latest_ami_id(role), instance_type, launch_configuration_name(role))                                        ; rescue StandardError => e ;  puts e ; end
    begin auto_scale.update_auto_scaling_group(autoscale_group_name(role),{"LaunchConfigurationName" => launch_configuration_name(role),'MaxSize'=>500,'MinSize'=>2, 'DefaultCooldown'=>0})  ; rescue StandardError => e ;  puts e ; end
  end

  def delete_autoscale(role)
    begin auto_scale.update_auto_scaling_group(autoscale_group_name(role),{"LaunchConfigurationName" => launch_configuration_name(role),'MaxSize'=>0,'MinSize'=>0}) ; rescue StandardError => e ;  puts e ; end
      load_balancer = describe_load_balancer
      unless(load_balancer.nil?)
        loadbalancer_instances = load_balancer.body['DescribeLoadBalancersResult']['LoadBalancerDescriptions'].first['Instances']
        loadbalancer_instances.each do |instance|
          deregister_instance_from_elb(instance)
          terminate_instance(instance.to_s)
        end
      end
    begin delete_auto_scaling_policy(role, 'ScaleUp')   ; rescue StandardError => e ;  puts e ; end
    begin delete_auto_scaling_policy(role, 'ScaleDown') ; rescue StandardError => e ;  puts e ; end
    begin delete_auto_scaling_group(role)               ; rescue StandardError => e ;  puts e ; end
    begin delete_launch_configuration(role)             ; rescue StandardError => e ;  puts e ; end
   end

  def delete_load_balancer
    elb.delete_load_balancer(load_balancer_name)
  end

  def delete_launch_configuration(role)
    auto_scale.delete_launch_configuration(launch_configuration_name(role))
  end

  def delete_auto_scaling_group(role)
   auto_scale.delete_auto_scaling_group(role+'_group')
  end

  def delete_auto_scaling_policy(role,policy_name)
    auto_scale.delete_policy(role+'_group', policy_name)
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

  def instance_health(load_balancer, instance)
    elb.describe_instance_health(load_balancer.id, instance.id).body['DescribeInstanceHealthResult']['InstanceStates'][0]['State']
  end

  def get_load_balancer_by_name(load_balancer_name)
     lbs = {}
     elb.load_balancers.each do |load_balancer|
       lbs[load_balancer.id] = load_balancer
     end
       lbs[load_balancer_name]
  end

  def get_load_balancer_by_instance(instance_id)
    hash = elb.load_balancers.inject({}) do |collect, load_balancer|
      load_balancer.instances.each {|load_balancer_instance_id| collect[load_balancer_instance_id] = load_balancer}
      collect
    end
     hash[instance_id]
  end

end

