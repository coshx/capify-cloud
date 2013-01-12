
require 'spec_helper'

describe "Capify" do

  before(:all) do
    @prototype_instance = mock_new_prototype_instance
    @prototype = capify.create_image(@prototype_instance)
  end

  describe "find_instance_by_ip"  do

    let(:prototype) {@prototype_instance}
    let(:ip) {prototype.public_ip_address}

    it "returns a Fog Server" do
      capify.find_instance_by_ip(ip).should be_an_instance_of(Fog::Compute::AWS::Server)
    end

    it "returns correct server containing the specified ip" do
      capify.find_instance_by_ip(ip).public_ip_address.should eql(ip)
    end

  end

  describe "prototype" do

    let(:server){capify.prototype}

    it "returns a Fog Server" do
      server.should be_an_instance_of(Fog::Compute::AWS::Server)
    end

    it "returns server with correct Options tag" do
      server.tags['Options'].should eql('prototype')
    end

    it "returns server with correct role" do
       server.tags['Roles'].should include capify.role
    end

  end

end