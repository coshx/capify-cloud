require 'spec_helper'


describe "Capify" do

  before (:all) do
    Fog.mock!
    capify.stage = 'sandbox'
    capify.role = 'app'
    @loadbalancer = capify.create_loadbalancer
   end

  describe "create_loadbalancer" do
    it "returns a Fog loadbalancer" do
      @loadbalancer.should be_an_instance_of(Fog::AWS::ELB::LoadBalancer)
    end
  end

  describe "update_loadbalancer" do

      before (:each) do
        Fog.should_receive(:wait_for).at_least(:once).and_return(true)
      end

      it "replaces outdated instances with instances from new ami" do
        pending("Fog::AWS::AutoScaling::Mock#execute_policy (not implemented)")
      end

  end

end