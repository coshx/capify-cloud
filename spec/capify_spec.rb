require 'rubygems'
require 'json'
require_relative '../lib/capify-cloud'

key = { :aws_secret_access_key => 'aws_secret_access_key', :aws_access_key_id => 'aws_access_key_id', :provider => "AWS" }

def compute
  @compute ||= Fog::Compute.new(key)
end

def new_instance(compute)
  server_data = compute.run_instances('ami-e565ba8c', 1, 1,'InstanceType' => 'm1.large','SecurityGroup' => 'application','Placement.AvailabilityZone' => 'us-east-1a').body['instancesSet'].first
  sleep 3
  instance = compute.describe_instances('instance-id' => server_data['instanceId']).body['reservationSet'].first['instancesSet'].first['instanceId']
  compute.create_tags(instance, {"Roles"=> "web, app, worker"})
  compute.create_tags(instance, {"Project"=> "example_project"})
end

describe "Cap" do
  before (:all) do
    Fog.mock!
    Cap = CapifyCloud.new(File.dirname(File.expand_path(__FILE__)) + '/support/cloud.yml' )
    new_instance(Cap.compute)
end

  describe "create_ami_image" do

    it "returns a Excon::Response object" do

    end

  end


end