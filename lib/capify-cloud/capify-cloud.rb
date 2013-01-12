require File.expand_path(File.dirname(__FILE__) + '/lib/images')
require File.expand_path(File.dirname(__FILE__) + '/lib/instances')
require File.expand_path(File.dirname(__FILE__) + '/lib/autoscaling')
require File.expand_path(File.dirname(__FILE__) + '/lib/elb')

class CapifyCloud

  require 'fog'

  def initialize(cloud_config) @cloud_config = YAML.load_file cloud_config end
  def stage=(stage); @deploy_stage = stage end
  def role=(role); @deploy_role = role end
  def stage ; @deploy_stage || 'sandbox' end
  def role ; @deploy_role || 'app' end
  def application_name ; @cloud_config[:application] end
  def params ; @cloud_config[:AWS][stage.to_sym][:params] end
  def availability_zone ; params[:availability_zone] end
  def database ; params[:DB_HOST] end

  def create_image(prototype_instance)  ; images.create(prototype_instance)                         end
  def create_autoscale(image)           ; autoscale.create(image, stage)                            end
  def update_autoscale(image)           ; autoscale.update(image)                                   end
  def create_loadbalancer               ; elb.create(availability_zone)                             end
  def update_loadbalancer(image)        ; elb.update(image)                                         end
  def cleanup                           ; autoscale.cleanup                                         end
  def print_autoscale                   ; autoscale.print_autoscale                                 end
  def print_configuration               ; autoscale.print_configuration                             end
  def print_images                      ; images.print_images                                       end
  def print_snapshots                   ; images.print_snapshots                                    end
  def print_prototypes                  ; instances.print_prototypes                                end
  def print_groups                      ; autoscale.print_groups                                    end
  def prototype                         ; instances.find_prototype_by_role_and_stage(role, stage)   end
  def find_instance_by_ip(ip)           ; instances.find_by_ip(ip)                                  end
  def web_instances                     ; instances.find_web_on_current_stage(stage)                end

  def set10 ; autoscale.set_capacity_to_ten  end
  def set1 ; autoscale.set_capacity_to_one  end


  private

  def compute_connection ; @compute_connection ||= Fog::Compute.new(:provider => :AWS, :aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id],:aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key], :region => @cloud_config[:AWS][stage.to_sym][:params][:region]) end
  def autoscale_connection; @autoscale_connection ||=Fog::AWS::AutoScaling.new(:aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id],:aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key]) end
  def elb_connection; @elb_connection ||= Fog::AWS::ELB.new(:aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id], :aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key], :region => @cloud_config[:AWS][stage.to_sym][:params][:region]) end

  def instances ; @instances ||= Instances.new(compute_connection) end
  def images ; @images ||= Images.new(compute_connection, role, stage, application_name) end
  def autoscale ; @autoscale ||= Autoscale.new(autoscale_connection, compute_connection, params, role, stage) end
  def elb ; @elb ||= Elb.new(elb_connection, compute_connection, autoscale_connection, params, role, stage) end

end

#todo separating according to  instances, images, autoscale, elb proving to be bad design
#todo cloud.yml variables within elb.get_listener_array
#todo cloud.yml variables within autoscale.create - put_scaling_policy - scaleup/down increment
#todo batch instance replacement




