require 'rubygems'
require 'json'
require_relative '../lib/capify-cloud'
key = { :aws_secret_access_key => 'aws_secret_access_key', :aws_access_key_id => 'aws_access_key_id', :provider => "AWS" }

describe "Cap" do
  before (:all) do
   Fog.mock!
   compute = Fog::Compute.new(key)
   server_data = compute.run_instances(
       'ami-e565ba8c', 1, 1,
       'InstanceType' => 'm1.large',
       'SecurityGroup' => 'application',
       'Placement.AvailabilityZone' => 'us-east-1a'
    ).body['instancesSet'].first
    sleep 3
   instance = compute.describe_instances('instance-id' => server_data['instanceId']).body['reservationSet'].first['instancesSet'].first['instanceId']
   compute.create_tags(instance, {"Roles"=> "web, app, worker"})
   compute.create_tags(instance, {"Project"=> "example_project"})
   Cap = CapifyCloud.new(File.dirname(File.expand_path(__FILE__)) + '/support/cloud.yml')
end

  describe "cloud:create_ami" do

    it "returns a Excon::Response object containing valid json" do
      pending("waiting on successful Cap.create_ami(\"web\")")
      @create_ami_response = Cap.create_ami("web")
      json_object = JSON.parse(@create_ami_response.body.to_json)
      json_object.should_not be_nil
    end

  end
end