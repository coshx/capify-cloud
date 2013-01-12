
require 'json'
require_relative '../lib/capify-cloud/capify-cloud'
require "rake"
require "rspec/core/rake_task"

def capify
  @capify ||= CapifyCloud.new(File.dirname(File.expand_path(__FILE__)) + '/support/cloud.yml' )
end

def compute_connection
  @compute_connection ||= capify.instance_eval{compute_connection}
end

def elb_connection
  @elb_connection ||= capify.instance_eval{elb_connection}
end

def autoscale_connection
  @autoscale_connection ||= capify.instance_eval{autoscale_connection}
end

def mock_new_prototype_instance
    server_data = compute_connection.run_instances('ami-e565ba8c', 1, 1,'InstanceType' => 'm1.large','SecurityGroup' => 'application','Placement.AvailabilityZone' => 'us-east-1a').body['instancesSet'].first
    sleep 3 ; instance_id = compute_connection.describe_instances('instance-id' => server_data['instanceId']).body['reservationSet'].first['instancesSet'].first['instanceId']
    compute_connection.create_tags(instance_id, {"Roles"=> "app"})
    compute_connection.create_tags(instance_id, {"Stage"=> "sandbox"})
    compute_connection.create_tags(instance_id, {"Options"=> "prototype"})
    compute_connection.servers.get(instance_id)
end

def convert_tag_array_to_hash(array)
  tags = {}
  array.tags.each do |keyset|
      hash = { keyset['key'] => keyset['value'] }
      tags = tags.merge(hash)
    end
    return tags
end

def all_launch_configurations
  autoscale_connection.describe_launch_configurations.body['DescribeLaunchConfigurationsResult']['LaunchConfigurations']
end

def autoscaling_group
  begin
    autoscale_connection.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult']['AutoScalingGroups'].first['AutoScalingGroupName']
  rescue Exception
    return nil
  end
end

def snapshot_id_of_ami(image_id)
    ami = @compute_connection.images.get(image_id)
    unless ami.nil? || ami.block_device_mapping.first.nil?
      return ami.block_device_mapping.first['snapshotId']
    else
      return '- snapshot unavailable -'
    end
end

RSpec.configure do |config|

  config.before (:each) do
    Fog.mock!
    capify.stage = 'sandbox'
    capify.role = 'app'
  end

  config.after(:each) do
    compute_connection.terminate_instances(@prototype_instance.id) if @prototype_instance
    compute_connection.deregister_image(@prototype_image.id) if @prototype_image
    compute_connection.deregister_image(@updated_prototype_image.id) if @updated_prototype_image
    elb_connection.delete_load_balancer(@loadbalancer) if @loadbalancer
    autoscale_connection.delete_auto_scaling_group(autoscaling_group) if !autoscaling_group.nil?

    all_launch_configurations.each do |configs|
      configs.select {|f| f["LaunchConfigurationName"] }.each do |key,launch_config_name|
          autoscale_connection.delete_launch_configuration(launch_config_name)
       end
    end
  end



end