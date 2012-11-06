require 'rubygems'
require 'json'
require_relative '../lib/capify-cloud'
require_relative '../spec/support/IAM_helper'

def capify
  @capify_cloud ||= CapifyCloud.new(File.dirname(File.expand_path(__FILE__)) + '/support/cloud.yml' )
end

def compute
  capify.instance_eval{compute_connection}
end

def config
  capify.instance_eval{cloud_config}
end

def config_params
  capify.config_params
end

def run_new_prototype
  server_data = compute.run_instances('ami-e565ba8c', 1, 1,'InstanceType' => 'm1.large','SecurityGroup' => 'application','Placement.AvailabilityZone' => 'us-east-1a').body['instancesSet'].first
  sleep 3
  instance_id = compute.describe_instances('instance-id' => server_data['instanceId']).body['reservationSet'].first['instancesSet'].first['instanceId']
  compute.create_tags(instance_id, {"Roles"=> "app"})
  compute.create_tags(instance_id, {"Stage"=> "sandbox"})
  compute.create_tags(instance_id, {"Options"=> "prototype"})
  return compute.servers.get(instance_id)
end

def tags_to_hash(array)
  tags = {}
  array.tags.each do |keyset|
    hash = { keyset['key'] => keyset['value'] }
    tags = tags.merge(hash)
  end
  return tags
end

describe "Capify" do

  before (:all) do
     Fog.mock!
     capify.stage = 'sandbox'
     capify.role = 'app'
     @prototype = run_new_prototype()
     @image = capify.create_image(@prototype)
  end

  describe "create_loadbalancer" do

    it "returns a Fog loadbalancer" do
      load_balancer = capify.create_loadbalancer(capify.stage)
      load_balancer.should be_an_instance_of(Fog::AWS::ELB::LoadBalancer)
    end

  end

  describe "image_create" do
    let(:prototype) {@prototype}
    let(:image) {@image}

    it "returns a Fog Image" do
      image.should be_an_instance_of(Fog::Compute::AWS::Image)
    end

    it "creates image with same role and stage as the prototype" do
      image.tags['Roles'].should eql(prototype.tags['Roles'])
      image.tags['Stage'].should eql(prototype.tags['Stage'])
    end
  end

  describe "create_autoscale" do
    before(:all) do
      @create_autoscale_return = capify.create_autoscale(@image)
    end

    let(:image)                   {@image}
    let(:create_autoscale_return) {@create_autoscale_return}

    it "creates launch configuration containing the correct image id" do
      create_autoscale_return[:configuration].image_id.should eql(image.id)
    end

    it "creates autoscaling group with Options=>no_release" do
      tags = tags_to_hash(create_autoscale_return[:group])
      tags['Options'].should eql('no_release')
    end

    it "creates autoscaling group with role and stage specified by the launch configuration image_id" do
      tags = tags_to_hash(create_autoscale_return[:group])
      tags['Roles'].should eql(image.tags['Roles'])
      tags['Stage'].should eql(image.tags['Stage'])
    end

    it "creates an autoscaling group that propagate tags at launch" do
      create_autoscale_return[:group].tags.each do |hash|
        hash.has_key?('propagate_at_launch').should be_true
        hash['propagate_at_launch'].should eql('true')
      end
    end

  end

  describe "update_autoscale" do

    before(:all) do
      @updated_image = capify.create_image(@prototype)
      @update_autoscale_return = capify.update_autoscale(@updated_image)
    end

    let(:updated_image)           {@updated_image}
    let(:update_autoscale_return) {@update_autoscale_return}

    it "updates launch configuration with correct image id" do
      update_autoscale_return[:configuration].image_id.should eql(updated_image.id)
    end

  end


  describe "get_instance_by_ip"  do
    before(:all) do
    end

    let(:prototype) {@prototype}
    let(:ip) {prototype.public_ip_address}

    it "returns a Fog Server" do
      capify.get_instance_by_ip(ip).should be_an_instance_of(Fog::Compute::AWS::Server)
    end

    it "returns correct server containing the specified ip" do
      capify.get_instance_by_ip(ip).public_ip_address.should eql(ip)
    end

  end

  describe "get_prototype" do

    let(:server){capify.get_prototype(capify.role)}

    it "returns a Fog Server" do
      server.should be_an_instance_of(Fog::Compute::AWS::Server)
    end

    it "returns prototype server" do
      server.tags['Options'].should eql('prototype')
    end

    it "returns server with correct role" do
       server.tags['Roles'].should include capify.role
    end

  end

end

=begin
    #instance_id =  "i-#{Fog::Mock.random_hex(8)}"

    let(:stage) { capify.stage }
    let(:role) { capify.role }

    options = {:block_device_mappings => [{'DeviceName'=>'/dev/sdf1'}], 'KernelId' => 'kernal_id'}
    compute.create_image('instance_id', 'image_name', 'image_desc') #untagged image
    time = Time.now.utc.iso8601
    latest_version = time.gsub(':','.')
    earlier_version = Time.at(time.to_i-86400).to_s.gsub(':','.')
    first_tagged_image = compute.create_image('instance_id', 'image_name', 'image_desc',false, options)
    second_tagged_image = compute.create_image('instance_id', 'image_name', 'image_desc')
    compute.create_tags(first_tagged_image.body['imageId'], {'Stage' => stage, "Roles" => role, "Version"=> earlier_version})
    compute.create_tags(second_tagged_image.body['imageId'], {'Stage' => stage, "Roles" => role, "Version"=> latest_version})

  it "images returns available ami with proper stage and role" do
    #images = capify_cloud.images
    #images.images.count.should eql(2)
    #images.images.each do |image|
    #  image.roles.should include role
    #  image.stage.should eql(stage)
    #end
  end

  it "sorted_images return latest ami first" do
     #images = capify_cloud.Images.sorted_images
     #Time.parse(images[0].version.sub(".",":")).to_i.should > Time.parse(images[1].version.sub(".",":")).to_i
  end
=end




