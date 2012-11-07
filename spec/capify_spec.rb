require 'rubygems'
require 'json'
require_relative '../app/capify-cloud/capify-cloud'

describe "Capify" do

  before (:all) do
     Fog.mock!
     capify.stage = 'sandbox'
     capify.role = 'app'
     @prototype_instance = mock_new_prototype_instance()
     @prototype_image = capify.create_image(@prototype_instance)
  end

  let(:compute_connection) {capify.instance_eval{compute_connection}}
  let(:elb_connection) {capify.instance_eval{elb_connection}}
  let(:elb_class) {capify.instance_eval{elb}}

  describe "create_image" do

    let(:prototype_image){ @prototype_image }
    let(:prototype_instance){@prototype_instance}

    it "returns a Fog Image" do
      prototype_image.should be_an_instance_of(Fog::Compute::AWS::Image)
    end

    it "creates image with the same role and stage as it's prototype instance" do
      prototype_image.tags['Roles'].should eql(prototype_instance.tags['Roles'])
      prototype_image.tags['Stage'].should eql(prototype_instance.tags['Stage'])
    end
  end

  describe "create_loadbalancer" do
    it "returns a Fog loadbalancer" do
      capify.create_loadbalancer.should be_an_instance_of(Fog::AWS::ELB::LoadBalancer)
    end
  end

  describe "update_loadbalancer" do

    before (:each) do
      Fog.should_receive(:wait_for).and_return(true)
    end

    let(:load_balancer_name){"#{capify.stage}loadbalancer"}

    it "returns a Fog loadbalancer" do
      capify.update_loadbalancer.should be_an_instance_of(Fog::AWS::ELB::LoadBalancer)
    end

    it "removes and terminates any old instances in preparation for being replaced" do
      instance = compute_connection.run_instances('ami-e565ba8c', 1, 1,'InstanceType' => 'm1.large','SecurityGroup' => 'application','Placement.AvailabilityZone' => 'us-east-1a')#.body['instancesSet'].first
      elb_connection.register_instances(instance.body['instancesSet'].first['instanceId'], load_balancer_name)
      sleep 3
      capify.update_loadbalancer
      elb_instance_array = elb_class.instance_eval{loadbalancer}.instances
      instance_state = compute_connection.describe_instances('instance-id' => instance.body['instancesSet'].first['instanceId']).body['reservationSet'].first['instancesSet'].first['instanceState']['name']

      elb_instance_array.should be_empty
      instance_state.should eql('shutting-down')
    end

  end

  describe "create_autoscale" do

    before(:all) do
      @create_autoscale_return = capify.create_autoscale(@prototype_image)
    end

    let(:image)                   {@prototype_image}
    let(:create_autoscale_return) {@create_autoscale_return}

    it "returns a hash containing :group and :configuration" do
      create_autoscale_return.has_key?(:group).should be_true
      create_autoscale_return.has_key?(:configuration).should be_true
    end

    it "creates launch configuration containing the correct image id" do
      create_autoscale_return[:configuration].image_id.should eql(image.id)
    end

    it "creates an autoscaling group that propagate tags at launch" do
      create_autoscale_return[:group].tags.each do |hash|
        hash.has_key?('propagate_at_launch').should be_true
        hash['propagate_at_launch'].should eql('true')
      end
    end

    it "creates autoscaling group with Options=>no_release" do
      tags = convert_tag_array_to_hash(create_autoscale_return[:group])
      tags['Options'].should eql('no_release')
    end

    it "creates autoscaling group with role and stage specified by the launch configuration image_id" do
      tags = convert_tag_array_to_hash(create_autoscale_return[:group])
      tags['Roles'].should eql(image.tags['Roles'])
      tags['Stage'].should eql(image.tags['Stage'])
    end

  end

  describe "update_autoscale" do

    before(:all) do
      @updated_image = capify.create_image(@prototype_instance)
      @update_autoscale_return = capify.update_autoscale(@updated_image)
    end

    let(:updated_image)           {@updated_image}
    let(:update_autoscale_return) {@update_autoscale_return}

    it "returns a hash containing :group and :configuration" do
      update_autoscale_return.has_key?(:group).should be_true
      update_autoscale_return.has_key?(:configuration).should be_true
    end

    it "updates launch configuration with correct image id" do
      update_autoscale_return[:configuration].image_id.should eql(updated_image.id)
    end

  end


  describe "get_instance_by_ip"  do

    let(:prototype) {@prototype_instance}
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

def capify
  @capify ||= CapifyCloud.new(File.dirname(File.expand_path(__FILE__)) + '/support/cloud.yml' )
end


=begin
 "i-#{Fog::Mock.random_hex(8)}"
=end




