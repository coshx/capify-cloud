class Autoscale

  def initialize(connection, config_params, role, stage)
    @connection = connection
    @config_params = config_params
    @autoscale_group_name = "#{role}_#{stage}_group"
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
    @connection.create_launch_configuration(image.id, instance_type, launch_configuration_name, launch_options)
    @connection.update_auto_scaling_group(autoscale_group_name,{"LaunchConfigurationName" => launch_configuration_name, "MinSize" => min_instances, "MaxSize" => max_instances})
    return {:group => @connection.groups.get(@autoscale_group_name), :configuration => @connection.configurations.get(launch_configuration_name)}
  end

  private
  def instance_type ; @config_params[:instance_type] end
  def min_instances ; @config_params[:min_instances] || 1 end
  def max_instances ; @config_params[:max_instances] || 5 end
  def launch_options ; {'KernelId' => @config_params[:kernel_id], 'SecurityGroups' => @config_params[:security_group]} end
  def availability_zone ; @config_params[:availability_zone] end
  def autoscale_group_name ; @autoscale_group_name end
  def generate_launch_configuration_name(image) ; "#{image.id}_launchconfig" end
  def generate_tags(image_tags)
    autoscale_tags = []
    image_tags.each_pair do |k,v|
      autoscale_tags.push << {'key'=>k,'value'=>v, 'propagate_at_launch'=> 'true'}
    end
    return autoscale_tags
  end

end