class Elb

  def initialize(connection,config_params)
    @connection = connection
    @config_params = config_params
  end

  def create(stage)
    availability_zone = @config_params[:availability_zone]
    load_balancer_name = "#{stage}loadbalancer"
    listeners = get_listener_array()
    @connection.create_load_balancer(availability_zone, load_balancer_name, listeners)
    return @connection.load_balancers.get(load_balancer_name)
  end

  private
  def get_listener_array
    listeners = []
    listeners << {"Protocol"=>"HTTP", 'LoadBalancerPort' => 80,  "InstancePort"=>80}
    unless Fog.mocking?
      listeners << {"Protocol"=>"HTTPS", "InstanceProtocol"=>"HTTPS",'LoadBalancerPort' => 443, "SSLCertificateId"=>@config_params[:SSL_CERTIFICATE], "InstancePort"=>443}
    end
  end
end