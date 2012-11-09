require File.expand_path(File.dirname(__FILE__) + '/lib/images')
require File.expand_path(File.dirname(__FILE__) + '/lib/instances')
require File.expand_path(File.dirname(__FILE__) + '/lib/autoscaling')
require File.expand_path(File.dirname(__FILE__) + '/lib/elb')

class CapifyCloud
  require 'fog'

  def initialize(cloud_config) @cloud_config = YAML.load_file cloud_config end
  def stage=(stage); @deploy_stage = stage end
  def role=(role); @deploy_role = role end
  def stage ; @deploy_stage end
  def role ; @deploy_role end
  def application_name ; @cloud_config[:application] end
  def config_params ; @cloud_config[:AWS][stage.to_sym][:params] end

  def create_image(prototype_instance) ; images.create(prototype_instance) end
  def create_autoscale(image) ; autoscale.create(image, stage) end
  def update_autoscale(image) ; autoscale.update(image) end
  def create_loadbalancer ; elb.create(config_params[:availability_zone]) end
  def update_loadbalancer ; elb.update end
  def print_autoscale ; autoscale.print_autoscale() end
  def print_configuration ; autoscale.print_configuration() end
  def print_images ; images.print_images() end
  def print_snapshots ; images.print_snapshots() end
  def print_prototypes ; instances.print_prototypes() end
  def print_groups ; autoscale.print_groups() end
  def cleanup ; autoscale.cleanup() end
  def find_instance_by_ip(ip) ; instances.find_by_ip(ip) end
  def find_prototype_by_role(role) ; instances.find_prototype_by_role_and_stage(role, stage) end

  def get_instances_by_role(role)
      desired_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}
  end

  private
  def cloud_config ; @cloud_config end
  def instances ; @instances ||= Instances.new(compute_connection) end
  def images ; @images ||= Images.new(compute_connection,role, stage) end
  def autoscale ; @autoscale ||= Autoscale.new(autoscale_connection, compute_connection, config_params, role, stage) end
  def elb ; @elb ||= Elb.new(elb_connection, compute_connection, config_params, stage) end

  def compute_connection ; @compute_connection ||= Fog::Compute.new(:provider => :AWS, :aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id],:aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key], :region => @cloud_config[:AWS][stage.to_sym][:params][:region]) end
  def autoscale_connection; @autoscale_connection ||=Fog::AWS::AutoScaling.new(:aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id],:aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key]) end
  def elb_connection; @elb_connection ||= Fog::AWS::ELB.new(:aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id], :aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key], :region => @cloud_config[:AWS][stage.to_sym][:params][:region]) end

end


=begin

#todo cloud.yml variables within elb.get_listener_array
#todo cloud.yml variables within autoscale.create - put_scaling_policy - scaleup/down increment

 #compute.describe_instances('ip-address'=>ip).body['reservationSet'].first['instancesSet'].first['instanceId']


  def images ; @images || Images.new(compute) end
  def servers ; @autoscale || Servers.new(compute) end
  def autoscaling ; @autoscale || Autoscaling.new(compute) end
  def loadbalancing ; @autoscale || Loadbalancing.new(compute) end


  cloud.remove_outdated_ami
        cloud.describe_auto_scaling_groups.body['DescribeAutoScalingGroupsResult'].each do |auto_scaling_group|
          auto_scaling_group.each do |group|
            if(group.is_a?(Array))
              group.select {|f| f["AutoScalingGroupName"] }.each do |array|
                if array['Instances'].empty?
                  groupname = array['AutoScalingGroupName']
                  launchconfig = array['LaunchConfigurationName']
                  puts "deleting autoscale configuration "+groupname
                  cloud.delete_auto_scaling_group(groupname)
                  cloud.delete_launch_configuration(launchconfig)
                end
              end
            end
          end
        end

=end

