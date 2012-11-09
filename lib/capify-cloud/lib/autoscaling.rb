class Autoscale

  def initialize(connection,compute_connection, config_params, role, stage)
    @connection = connection
    @compute_connection = compute_connection
    @config_params = config_params
    @stage = stage
    @autoscale_group_name = "#{stage}_#{role}_group"
  end

  def create(image, load_balancer = nil)
    autoscale_tags = generate_tags(image.tags)
    launch_configuration_name = generate_launch_configuration_name(image)
    as_group_options = {'LoadBalancerNames'=>load_balancer, 'DefaultCooldown'=>0, 'Tags' => autoscale_tags }
    @connection.create_launch_configuration(image.id, instance_type, launch_configuration_name, launch_options)
    @connection.create_auto_scaling_group(autoscale_group_name, availability_zone, launch_configuration_name, max_instances, min_instances, as_group_options)
    @connection.put_scaling_policy('ChangeInCapacity', autoscale_group_name, 'ScaleUp', +1, {})
    @connection.put_scaling_policy('ChangeInCapacity', autoscale_group_name, 'ScaleDown', -1, {})
    return {:group => @connection.groups.get(@autoscale_group_name), :configuration => @connection.configurations.get(launch_configuration_name)}
  end

  def update(image)
    launch_configuration_name = generate_launch_configuration_name(image)
    puts "  creating new launch configuration #{launch_configuration_name}"
    @connection.create_launch_configuration(image.id, instance_type, launch_configuration_name, launch_options)
    @connection.update_auto_scaling_group(autoscale_group_name,{"LaunchConfigurationName" => launch_configuration_name, "MinSize" => min_instances, "MaxSize" => max_instances})
    return {:group => @connection.groups.get(@autoscale_group_name), :configuration => @connection.configurations.get(launch_configuration_name)}
  end

  def cleanup
    puts "  cleaning up"
    active_configurations = active_launch_configurations()
    all_launch_configurations.each do |configs|
      configs.select {|f| f["LaunchConfigurationName"] }.each do |key,launch_config_name|
        if !active_configurations.include? (launch_config_name)
          image_id = @connection.configurations.get(launch_config_name).image_id
          snapshot_id = snapshot_id_of_ami(image_id)
          puts "  deleting #{launch_config_name}, #{image_id} and #{snapshot_id}"
          @compute_connection.deregister_image(image_id)
          @compute_connection.delete_snapshot(snapshot_id)
          @connection.delete_launch_configuration(launch_config_name)
        end
      end
    end
  end

  def print_groups
    autoscaling_groups.each do |auto_scaling_group|
      auto_scaling_group.select {|g| g.is_a? Array}.each do |group|
        group.select {|f| f["AutoScalingGroupName"] }.each do |array|
          puts "  #{array['AutoScalingGroupName']}"
        end
      end
    end
  end

  def print_configuration
    puts "  launch configuration files"
    active = active_launch_configurations
    all_launch_configurations.each do |config|
      launch_name = config['LaunchConfigurationName']
      image = @compute_connection.images.get(config['ImageId'])
      puts "    #{launch_name} #{if active.include?(launch_name);'(active)' end} -> #{config['ImageId']} #{if image.nil?; ' (image unavailable)' else '(image available)'end}"
    end
  end

  def print_autoscale
    autoscaling_groups.each do |auto_scaling_group|
      auto_scaling_group.select {|g| g.is_a? Array}.each do |group|
        group.select {|f| f["AutoScalingGroupName"] }.each do |array|
          groupname = array['AutoScalingGroupName']
          launchconfig = array['LaunchConfigurationName']
            puts "load balancer: #{array['LoadBalancerNames'].first}"
            puts "  autoscaling group: #{groupname}"
            puts "    launchconfig: #{launchconfig} - #{array['Instances'].count} instances"
            array['Instances'].each do |instances|
              instances.select {|f| f["InstanceId"] }.each do |key,instance_id|
                instance = @compute_connection.servers.get(instance_id)
                  puts "      instance: #{instance.id} -> #{instance.image_id} -> #{snapshot_id_of_ami(instance.image_id)}"
              end
            end
          end
        end
      end
    end
  end

  private

  def all_launch_configurations
    @connection.describe_launch_configurations.body['DescribeLaunchConfigurationsResult']['LaunchConfigurations']
  end

  def autoscaling_groups
    @connection.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult']
  end

  def active_launch_configurations
    configuration = []
    autoscaling_groups.each do |auto_scaling_group|
      auto_scaling_group.select {|g| g.is_a? Array}.each do |group|
        group.select {|f| f["AutoScalingGroupName"] }.each do |array|
          configuration.push(array['LaunchConfigurationName'])
        end
      end
    end
    return configuration
  end

  def snapshot_id_of_ami(image_id)
    ami = @compute_connection.images.get(image_id)
    if !ami.nil?
      return ami.block_device_mapping.first['snapshotId']
    else
      return '- snapshot unavailable -'
    end
  end

  def instance_type ; @config_params[:instance_type] end
  def min_instances ; @config_params[:min_instances] || 1 end
  def max_instances ; @config_params[:max_instances] || 5 end
  def launch_options ; {'KernelId' => @config_params[:kernel_id], 'SecurityGroups' => @config_params[:security_group]} end
  def availability_zone ; @config_params[:availability_zone] end
  def autoscale_group_name ; @autoscale_group_name end
  def generate_launch_configuration_name(image) ; "#{@stage}_launchconfig_#{image.id}" end
  def generate_tags(image_tags)
    autoscale_tags = []
    image_tags.each_pair do |k,v|
      autoscale_tags.push << {'key'=>k,'value'=>v, 'propagate_at_launch'=> 'true'}
    end
    return autoscale_tags
  end

