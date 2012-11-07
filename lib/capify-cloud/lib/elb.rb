
class Elb

  def initialize(elb_connection, compute_connection, stage)
    @elb_connection = elb_connection
    @compute_connection = compute_connection
    @loadbalancer_name = "#{stage}loadbalancer"
  end

  def create(availability_zone)
    @elb_connection.create_load_balancer(availability_zone, @loadbalancer_name , generate_listener_array)
    return loadbalancer
  end

  def update
    instances = loadbalancer.instances
    instance_count = instances.count
    loadbalancer.deregister_instances(instances)
    @compute_connection.terminate_instances(instances)
    wait_for_load_balancer_to_replace_instances(instance_count)
    return loadbalancer
  end

  private

  def wait_for_load_balancer_to_replace_instances(instance_count)
    string = ''
    Fog.wait_for do
      string = write_progress(string)+"---"
      load_balancer_healthy?(instance_count)
    end
  end
  def write_progress(string)
    string = string+".";
    if string.length>10
      string = ''
    end
    STDOUT.write "\r#{string}"
    return string
  end
  def loadbalancer ; @elb_connection.load_balancers.get(@loadbalancer_name) end
  def load_balancer_healthy?(instance_count)
    return false unless loadbalancer.instances.count == instance_count
    loadbalancer.instances.each do |instance|
      inservice = @elb_connection.describe_instance_health(load_balancer_name, instance).body['DescribeInstanceHealthResult']['InstanceStates'][0]['State']!='InService'
      running = @compute_connection.describe_instances('instance-id' => instance).body['reservationSet'].first['instancesSet'].first['instanceState']['name'] == 'running'
      return false unless inservice && running
    end
    return true
  end

  def generate_listener_array
    listeners = []
    listeners << {"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80}
    unless Fog.mocking?
      listeners << {"Protocol"=>"HTTPS", "InstanceProtocol"=>"HTTPS",'LoadBalancerPort' => 443, "SSLCertificateId"=>@config_params[:SSL_CERTIFICATE], "InstancePort"=>443}
    end
  end

end