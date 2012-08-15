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
  end

  def instances
    return @instances unless @instance.nil?
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
    return @instances
  end

  def compute
    config = @cloud_config[:AWS]
    @compute ||= Fog::Compute.new(:provider => :AWS, :aws_access_key_id => config[:aws_access_key_id],:aws_secret_access_key => config[:aws_secret_access_key], :region => config[stage.to_sym][:params][:region])
  end

  def auto_scale
    config = @cloud_config[:AWS]
    @autoscale ||=Fog::AWS::AutoScaling.new(:aws_access_key_id => config[:aws_access_key_id],:aws_secret_access_key => config[:aws_secret_access_key])
  end
  def elb
    config = @cloud_config[:AWS]
    @elb ||= Fog::AWS::ELB.new(:aws_access_key_id => config[:aws_access_key_id], :aws_secret_access_key => config[:aws_secret_access_key], :region => config[stage.to_sym][:params][:region])
  end
  def cloudwatch
    config = @cloud_config[:AWS]
    @cloudwatch ||= Fog::AWS::CloudWatch.new(:aws_access_key_id => config[:aws_access_key_id], :aws_secret_access_key => config[:aws_secret_access_key], :region => config[stage.to_sym][:params][:region])
  end

  def define_stage(stage)
    @stage = stage
  end

  def define_role(role)
    @deploy_role = role
  end

  def stage
    @stage || "staging"
  end

  def role
    @deploy_role || :app
  end

  def project_tag
    return @project_tag ||= @cloud_config[:AWS][stage.to_sym][:project_tag]
  end

  def image_state(ami)
    compute.describe_images('image-id' => ami.body['imageId']).body['imagesSet'].first['imageState']
  end

  def image_tags(ami)
    compute.describe_images('image-id' => ami).body['imagesSet'].first["tagSet"]
  end

  def compute_state(instance)
      compute.describe_instances( 'instance-id' => instance).body['reservationSet'].first['instancesSet'].first['instanceState']['name']
  end

  def project_ami
    compute.describe_images('tag:Project' => project_tag)
  end

  def server_names
    desired_instances.map {|instance| instance.name}
  end

  def project_instances
    instances.select {|instance| instance.tags["Project"] == project_tag}
  end

  def primary_instances
     project_instances.select {|instance| instance.tags['Options'].split(%r{,\s*}).include?('primary') rescue false}
  end

  def desired_instances
    project_tag.nil? ? instances : project_instances
  end

  def get_instance_by_id(id)
    desired_instances.select {|instance| instance.id == id}.first
  end

  def get_instances_by_role(role)
    desired_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}
  end

  def get_instances_by_region(roles, region)
    return unless region
    desired_instances.select {|instance| instance.availability_zone.match(region) && instance.roles == roles.to_s rescue false}
  end

  def determine_regions(cloud_provider = 'AWS')
    @cloud_config[cloud_provider.to_sym][stage.to_sym][:params][:regions] || [@cloud_config[cloud_provider.to_sym][stage.to_sym][:params][:region]]
  end

  def describe_cloudwatch_alarms(options = {})
    cloudwatch.describe_alarms(options)
  end

  def describe_load_balancers(options = {})
    elb.describe_load_balancers(options)
  end

  def describe_load_balancer(load_balancer_name)
    begin elb.describe_load_balancers({"LoadBalancerNames" => load_balancer_name}) ; rescue StandardError => e ;  puts e ; end
  end

  def describe_auto_scaling_groups(options = {})
    auto_scale.describe_auto_scaling_groups(options)
  end

  def describe_auto_scaling_policies(options = {})
    auto_scale.describe_policies(options)
  end

  def describe_autoscale_group
    begin auto_scale.describe_auto_scaling_groups('AutoScalingGroupNames' => role+'_group')  ; rescue StandardError => e ;  puts e ; end
  end

  def describe_launch_configurations(options ={})
    begin auto_scale.describe_launch_configurations(options)  ; rescue StandardError => e ;  puts e ; end
  end

  def describe_instance(instance_id)
    compute.describe_instances('instance-id' => instance_id ).body
  end

  def delete_load_balancer
    elb.delete_load_balancer(load_balancer_name)
  end

  def delete_launch_configuration(launch_configuration_name = (role.to_s+'_launch_configuration_'+find_latest_ami))
    auto_scale.delete_launch_configuration(launch_configuration_name)
  end

  def delete_auto_scaling_group(group_name = role.to_s+'_group')
      auto_scale.delete_auto_scaling_group(group_name)
  end

  def delete_auto_scaling_policy(policy_name)
    auto_scale.delete_policy(role.to_s+'_group', policy_name)
  end

  def primary_instance
    role_primary_instance = primary_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false }
    if(role_primary_instance.nil?)
      puts "Cannot configure autoscaling: No primary instance tagged with the #{role} role."
      return
    elsif (role_primary_instance.size > 1)
      puts "Cannot configure autoscaling: More than one primary instance is tagged with the #{role} role."
      return
    end
    return role_primary_instance.first
  end

  def display_instances
    desired_instances.each_with_index do |instance, i|
      puts sprintf "%02d:  %-40s  %-20s %-20s  %-20s  %-25s  %-20s  (%s)  (%s)",
      i, (instance.name || "").green, instance.provider.yellow, instance.id.red, instance.flavor_id.cyan,
      instance.contact_point.blue, instance.zone_id.magenta, (instance.tags["Roles"] || "").yellow,
      (instance.tags["Options"] || "").yellow
    end
  end

  def find_latest_ami
    images = Array.new
    ami = project_ami
    unless ami.nil?
      ami.body['imagesSet'].each do |image|
        unless image["tagSet"].empty?
          images.push(image) if image["tagSet"]["Roles"].include? role.to_s
        end
      end
    end
    if images.any?
      images = images.sort{|image1,image2| Time.parse(image2["tagSet"]["Version"]).to_i <=> Time.parse(image1["tagSet"]["Version"]).to_i}
      images[0]["imageId"]
    else
      puts "no images with #{role} role"
    end
  end

  def autoscale_deploy
    new_version = Time.now.utc.iso8601.gsub(':','.')

    compute.delete_tags(primary_instance.id,"Version"=> primary_instance.tags['Version'])
    compute.create_tags(primary_instance.id,"Version"=> new_version)
    ami = create_ami
    if ami.nil?
      return
    end
    ami_tags = {"Name"=>role.to_s+'.'+primary_instance.tags["Project"],"Project" => primary_instance.tags["Project"], "Roles" => primary_instance.tags['Roles'], "Version" => new_version, "Options" => "no_release"}
    compute.create_tags(ami.body['imageId'], ami_tags)
    if image_tags(ami.body['imageId']).empty?
      puts "image tag creation failed, please try again in a few minutes."
      return
    end
    update_autoscale(ami.body['imageId'])
  end

  def create_ami
    ami = compute.create_image(primary_instance.id,"#{Time.now.utc.iso8601.gsub(':','.')}", "#{Time.now.utc.iso8601.gsub(':','.')}")
    puts "creating new ami, this could take a while..."
    progress_output = "."
    Fog.wait_for do
      STDOUT.write "\r#{progress_output}"
      progress_output = progress_output+"."
      if progress_output.length>10
        progress_output = ''
      end
      image_state(ami) != 'pending'
    end
    if image_state(ami) == 'failed'
      puts "image creation failed, please try exec cap #{project_tag} #{role.to_s} autoscale:deploy again in a few minutes."
      return nil
    else
      puts "\nami ok: "+ami.body['imageId']
      return ami
    end
  end

  def terminate_instance(instance)
    compute.terminate_instances(instance).body['instancesSet'].first
    Fog.wait_for do
      compute_state(instance) == 'terminated'
    end
  end

  def create_load_balancer
    load_balancer_name = project_tag.gsub(/(\W|\d)/, "")
    zone = @cloud_config[:AWS][stage.to_sym][:params][:availability_zone]
    listeners = Array.new
    listeners.push({"Protocol"=>"HTTPS", 'LoadBalancerPort' => 443, "SSLCertificateId"=>"arn:aws:iam::710121801201:server-certificate/NetworkCert", "InstancePort"=>443})
    listeners.push({"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80})
    elb.create_load_balancer(zone, load_balancer_name, listeners)
  end

  def create_autoscale(latest_ami = find_latest_ami)
    instance_type = @cloud_config[:AWS][stage.to_sym][:params][:instance_type]
    zone = @cloud_config[:AWS][stage.to_sym][:params][:availability_zone]
    existing_ami_tags = image_tags(latest_ami)
    launch_configuration_name = stage.to_s+"_"+role.to_s+'_launch_configuration_'+latest_ami
    autoscale_group_name = stage.to_s+"_"+role.to_s+'_group'
    autoscale_tags = Array.new
    autoscale_tags.push({'key'=>"Name", 'value' => 'autoscale '+role.to_s+'.'+existing_ami_tags['Project']})
    existing_ami_tags.each_pair do |k,v|
        autoscale_tags.push({'key'=>k,'value'=>v, 'propagate_at_launch'=> 'true'})
    end
    launch_options = {'KernelId'=>'aki-825ea7eb','KeyName' => 'dev-coshx'}
    if @cloud_config[:AWS][stage.to_sym][:params][:load_balanced].include? role.to_s
      create_load_balancer
      load_balancer_name = project_tag.gsub(/(\W|\d)/, "")
      as_group_options = {'LoadBalancerNames'=>load_balancer_name,'DefaultCooldown'=>0, 'Tags' => autoscale_tags }
    else
      as_group_options = {'DefaultCooldown'=>0, 'Tags' => autoscale_tags }
    end
    begin
      auto_scale.create_launch_configuration(latest_ami, instance_type, launch_configuration_name,launch_options)
      auto_scale.create_auto_scaling_group(autoscale_group_name, zone, launch_configuration_name, max = 500, min = 2, as_group_options)
      auto_scale.put_scaling_policy('ChangeInCapacity', autoscale_group_name, 'ScaleUp', scaling_adjustment = 1, {})
      auto_scale.put_scaling_policy('ChangeInCapacity', autoscale_group_name, 'ScaleDown', scaling_adjustment = -1, {})
    rescue StandardError => e ;  puts e ; end
  end

  def update_autoscale(latest_ami = find_latest_ami)
    instance_type = @cloud_config[:AWS][stage.to_sym][:params][:instance_type]
    launch_configuration_name = (stage.to_s+"_"+role.to_s+'_launch_configuration_'+latest_ami)
    autoscale_group_name = stage.to_s+"_"+role.to_s+'_group'
    begin
      auto_scale.create_launch_configuration(latest_ami, instance_type, launch_configuration_name) ;
      auto_scale.update_auto_scaling_group(autoscale_group_name,{"LaunchConfigurationName" => launch_configuration_name})
    rescue StandardError => e ;  puts e ; end
  end

  def delete_autoscale
    autoscale_group_name = role.to_s+'_group'
    launch_configuration_name = (role.to_s+'_launch_configuration_'+find_latest_ami)
    options = {"LaunchConfigurationName" => launch_configuration_name,'MaxSize'=>0,'MinSize'=>0}
    begin auto_scale.update_auto_scaling_group(autoscale_group_name, options) ; rescue StandardError => e ;  puts e ; end
    load_balancer_name = project_tag.gsub(/(\W|\d)/, "")
    load_balancer = describe_load_balancer(load_balancer_name)
      unless(load_balancer.nil?)
        loadbalancer_instances = load_balancer.body['DescribeLoadBalancersResult']['LoadBalancerDescriptions'].first['Instances']
        loadbalancer_instances.each do |instance|
          deregister_instance_from_elb(instance)
          terminate_instance(instance.to_s)
        end
      end
    begin delete_auto_scaling_policy('ScaleUp') ; rescue StandardError => e ;  puts e ; end
    begin delete_auto_scaling_policy('ScaleDown') ; rescue StandardError => e ;  puts e ; end
    begin delete_auto_scaling_group   ; rescue StandardError => e ;  puts e ; end
    begin delete_launch_configuration ; rescue StandardError => e ;  puts e ; end
  end

  def deregister_instance_from_elb(instance_id)
    return unless @cloud_config[:AWS][stage.to_sym][:params][:load_balanced]
    instance = get_instance_by_id(instance_id)
    return if instance.nil?
    @@load_balancer = get_load_balancer_by_instance(instance.id)
    return if @@load_balancer.nil?
    elb.deregister_instances_from_load_balancer(instance.id, @@load_balancer.id)
  end

# @param instance_id [Object]
# @param load_balancer_name [Object]
  def register_instance_in_elb(instance_id, load_balancer_name = '')
   return if !@cloud_config[:AWS][stage.to_sym][:params][:load_balanced]
    instance = get_instance_by_id(instance_id)
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
      STDERR.puts "#{instance.name}: health tests timed out after #{time_elapsed} seconds."
    end
  end

  def autoscale_config_information
    describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
      puts "All existing autoscale configurations:"
      auto_scaling_group.each do |group|
        if(group.is_a?(Array))
          group.select {|f| f["AutoScalingGroupName"] }.each do |array|
            groupname = array['AutoScalingGroupName']
            launchconfig = array['LaunchConfigurationName']
            puts "  "+launchconfig
            puts "    "+groupname
            if array['Instances'].any?
              array['Instances'].each do |instances|
                instances.select {|f| f["InstanceId"] }.each do |key,instance|
                  puts "      "+instance
                end
              end
            end
          end
        end
      end
    end
  end

  def delete_all_autoscale_configuration
    describe_launch_configurations.body['DescribeLaunchConfigurationsResult']['LaunchConfigurations'].each do |configs|
      configs.select {|f| f["LaunchConfigurationName"] }.each do |key,config|
      puts config
        delete_launch_configuration(config)
      end
    end
  end

  def delete_all_autoscale_group_instances #does not delete primary instances
    describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
      auto_scaling_group.each do |group|
        if(group.is_a?(Array))
          group.select {|f| f["AutoScalingGroupName"] }.each do |array|
            launchconfig = array['LaunchConfigurationName']
            groupname = array['AutoScalingGroupName']
            if array['Instances'].any?
              array['Instances'].each do |instances|
                instances.select {|f| f["InstanceId"] }.each do |key,instance|
                  puts instance
                  if(!launchconfig.nil?)
                    options = {"LaunchConfigurationName" => launchconfig,'MaxSize'=>0,'MinSize'=>0}
                    begin auto_scale.update_auto_scaling_group(groupname, options) ; rescue StandardError => e ;  puts e ; end
                  end
                  deregister_instance_from_elb(instance)
                  terminate_instance(instance)
                end
              end
            end
          end
        end
      end
    end
  end

  def delete_all_autoscale_groups
    describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
      auto_scaling_group.each do |group|
        if(group.is_a?(Array))
          group.select {|f| f["AutoScalingGroupName"] }.each do |array|
            groupname = array['AutoScalingGroupName']
            puts groupname
            delete_auto_scaling_group(groupname)
          end
        end
      end
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