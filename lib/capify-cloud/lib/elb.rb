
class Elb

  def initialize(elb_connection, compute_connection, autoscale_connection, config_params, role, stage)
    @autoscale_connection = autoscale_connection
    @elb_connection = elb_connection
    @compute_connection = compute_connection
    @loadbalancer_name = "#{stage}networkunwastenyorg"
    @config_params = config_params
    @autoscale_group_name = "#{stage}_#{role}_group"
    @stage = stage

  end

  def create(availability_zone)
    @elb_connection.create_load_balancer(availability_zone, @loadbalancer_name, generate_listener_array)
    return loadbalancer
  end


  def update(image)
    instances = loadbalancer.instances
    instance_count = instances.count
    remove_old_instances(instances)
    add_back_new_instances(instance_count)
    @autoscale_connection.update_auto_scaling_group(autoscale_group_name,{"LaunchConfigurationName" => generate_launch_configuration_name(image),
                                                                              "MinSize" => @config_params[:min_instances], "MaxSize" => @config_params[:min_instances]})
    return loadbalancer
  end

  def instance_state(instance_id)
    @compute_connection.describe_instances('instance-id' => instance_id).body['reservationSet'].first['instancesSet'].first['instanceState']['name']
  end

  private
  def loadbalancer_name ; @loadbalancer_name end
  def loadbalancer ; @elb_connection.load_balancers.get(loadbalancer_name) end
  def generate_launch_configuration_name(image) ; "#{@stage}_launchconfig_#{image.id}" end
  def remove_old_instances(instances)
    #raising capacity causes all instances to be fired up at at the same time (so removing instance by lowering capacity to 0)
    puts '  removing old instances'  unless Fog.mocking?
    @autoscale_connection.put_scaling_policy('ExactCapacity', autoscale_group_name, 'RemoveAllPolicy', 0, {})
    @autoscale_connection.execute_policy("RemoveAllPolicy",'AutoScalingGroupName' => autoscale_group_name)
    Fog.wait_for do
      begin
        loadbalancer.instances.count == 0
      rescue Excon::Errors::InternalServerError => e
        false
      end
    end
    puts '  OK' unless Fog.mocking?
  end

  def add_back_new_instances(instance_count)
    puts '  firing up new instances' unless Fog.mocking?
    @autoscale_connection.put_scaling_policy('ExactCapacity', autoscale_group_name, 'ReplacementPolicy', instance_count, {})
    @autoscale_connection.execute_policy("ReplacementPolicy",'AutoScalingGroupName' => autoscale_group_name)
    Fog.wait_for do
      begin
        loadbalancer.instances.count == instance_count
      rescue Excon::Errors::InternalServerError => e
        false
      end
    end
    puts '  OK'  unless Fog.mocking?
  end

  def write_progress(string)
    string = string+".";
    if string.length>10
      string = ''
    end
    STDOUT.write "\r  #{string}" unless Fog.mocking?
    return string
  end

  def generate_listener_array
    listeners = []
    listeners << {"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80}
    unless Fog.mocking?
      listeners << {"Protocol"=>"HTTPS", "InstanceProtocol"=>"HTTPS",'LoadBalancerPort' => 443, "SSLCertificateId"=>@config_params[:SSL_CERTIFICATE], "InstancePort"=>443}
    end
  end
  def autoscale_group_name ; @autoscale_group_name end
  def generate_launch_configuration_name(image) ; "#{@stage}_launchconfig_#{image.id}" end
end