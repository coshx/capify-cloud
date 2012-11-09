
class Elb

  def initialize(elb_connection, compute_connection, config_params, stage)
    @elb_connection = elb_connection
    @compute_connection = compute_connection
    @loadbalancer_name = "#{stage}networkunwastenyorg"
    @config_params = config_params
  end

  def create(availability_zone)
    @elb_connection.create_load_balancer(availability_zone, @loadbalancer_name , generate_listener_array)
    return loadbalancer
  end

  def update
    instances = loadbalancer.instances
    instance_count = instances.count
    #run batch of new instances here to reduce wait time
    remove_old_instances(instances)
    wait_for_load_balancer_to_install_new_instances(instance_count)
    return loadbalancer
  end

  private
  def loadbalancer ; @elb_connection.load_balancers.get(@loadbalancer_name) end

  def remove_old_instances(instances)
    unless instances.count == 0
      puts "  removing old instances from the load balancer"
      loadbalancer.deregister_instances(instances)
      @compute_connection.terminate_instances(instances)
    end
  end

  def wait_for_load_balancer_to_install_new_instances(original_instance_count)
    if original_instance_count == 0  ; original_instance_count = @config_params[:min_instances] end
    puts "  waiting for #{original_instance_count} new servers to spin up - this could take a while"
    string = ''
    running_count = loadbalancer.instances.count
    Fog.wait_for do
      begin
        if loadbalancer.instances.count > running_count
          running_count = loadbalancer.instances.count
          STDOUT.write "\r  #{running_count} up"
          puts ""
        end
        string = write_progress(string)
        load_balancer_healthy?(original_instance_count)
      rescue Excon::Errors::InternalServerError => e
        false
      end
    end
  end

  def load_balancer_healthy?(original_instance_count)
   return false unless loadbalancer.instances.count == original_instance_count
    #loadbalancer.instances.each do |instance|
    #  inservice = @elb_connection.describe_instance_health(@loadbalancer_name, instance).body['DescribeInstanceHealthResult']['InstanceStates'][0]['State']!='InService'
    #  running = @compute_connection.describe_instances('instance-id' => instance).body['reservationSet'].first['instancesSet'].first['instanceState']['name'] == 'running'
    #  unless inservice && running
    #    return false
    #  end
    #end
    return true
  end

  def write_progress(string)
    string = string+".";
    if string.length>10
      string = ''
    end
    STDOUT.write "\r  #{string}"
    return string
  end

  def generate_listener_array
    listeners = []
    listeners << {"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80}
    unless Fog.mocking?
      listeners << {"Protocol"=>"HTTPS", "InstanceProtocol"=>"HTTPS",'LoadBalancerPort' => 443, "SSLCertificateId"=>@config_params[:SSL_CERTIFICATE], "InstancePort"=>443}
    end
  end

end