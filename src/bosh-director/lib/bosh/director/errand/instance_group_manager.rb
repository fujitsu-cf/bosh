module Bosh::Director
  class Errand::InstanceGroupManager
    def initialize(deployment, instance_group, logger)
      @deployment = deployment
      @instance_group = instance_group
      @logger = logger
      @disk_manager = DiskManager.new(logger)
      @template_blob_cache = @deployment.template_blob_cache
      agent_broadcaster = AgentBroadcaster.new
      @dns_encoder = LocalDnsEncoderManager.create_dns_encoder(@deployment.use_short_dns_addresses?)
      @powerdns_manager = PowerDnsManagerProvider.create
      @vm_deleter = VmDeleter.new(logger, false, Config.enable_virtual_delete_vms)
      @vm_creator = VmCreator.new(logger, @vm_deleter, @disk_manager, @template_blob_cache, @dns_encoder, agent_broadcaster)
    end

    def create_missing_vms
      @vm_creator.create_for_instance_plans(@instance_group.instance_plans_with_missing_vms, @deployment.ip_provider, @deployment.tags)
    end

    # Creates/updates all errand job instances
    # @return [void]
    def update_instances
      job_updater = JobUpdater.new(@deployment.ip_provider, @instance_group, @disk_manager, @template_blob_cache, @dns_encoder)
      job_updater.update
    end

    def delete_vms
      bound_instance_plans = @instance_group.needed_instance_plans.reject { |instance_plan| instance_plan.instance.model.nil? }
      if bound_instance_plans.empty?
        @logger.info('No errand vms to delete')
        return
      end

      bound_instance_plans.each do |instance_plan|
        instance_model = instance_plan.instance.model

        unless instance_plan.already_detached?
          DeploymentPlan::Steps::UnmountInstanceDisksStep.new(instance_model).perform
        end

        @vm_deleter.delete_for_instance(instance_model)
      end
    end

    private

    def bound_instance_plans
      @instance_group.needed_instance_plans.reject { |instance_plan| instance_plan.instance.model.nil? }
    end
  end
end
