class Workflow::Step::SubmitRequest < Workflow::Step
  REQUIRED_KEYS = [:source_project, :source_package, :target_project].freeze
  validate :validate_source_project_and_package_name

  def call
    return unless valid?

    @request_numbers_and_state_for_artifacts = {}
    case
    when scm_webhook.closed_merged_pull_request?
      revoke_submit_requests
    when scm_webhook.updated_pull_request?
      supersede_previous_and_submit_request
    when scm_webhook.new_pull_request?, scm_webhook.reopened_pull_request?, scm_webhook.push_event?, scm_webhook.tag_push_event?
      submit_package
    end
  end

  def artifact
    return { @bs_request.state => @bs_request.number } if @bs_request

    {}
  end

  private

  def bs_request_description
    step_instructions[:description] || workflow_run.event_source_message
  end

  def submit_package
    # let possible running source services finish, before submitting the sources
    Backend::Api::Sources::Package.wait_service(step_instructions[:source_project], step_instructions[:source_package])
    bs_request_action = BsRequestAction.new(source_project: step_instructions[:source_project],
                                            source_package: step_instructions[:source_package],
                                            target_project: step_instructions[:target_project],
                                            target_package: step_instructions[:target_package],
                                            source_rev: source_package_revision,
                                            type: 'submit')
    @bs_request = BsRequest.new(bs_request_actions: [bs_request_action],
                                description: bs_request_description)
    Pundit.authorize(@token.executor, @bs_request, :create?)
    @bs_request.save!

    Workflows::ScmEventSubscriptionCreator.new(token, workflow_run, scm_webhook, @bs_request).call
    SCMStatusReporter.new({ number: @bs_request.number, state: @bs_request.state }, scm_webhook.payload, @token.scm_token, workflow_run, 'Event::RequestStatechange').call
    @bs_request
  end

  def supersede_previous_and_submit_request
    # Fetch current open submit request which are going to be superseded
    # after the new sumbit request is created
    requests_to_be_superseded = submit_requests_with_same_target_and_source
    new_submit_request = submit_package

    requests_to_be_superseded.each do |submit_request|
      # Authorization happens on model level
      request = BsRequest.find_by_number!(submit_request.number)
      request.change_state(newstate: 'superseded',
                           reason: "Superseded by request #{new_submit_request.number}",
                           superseded_by: new_submit_request.number)
      (@request_numbers_and_state_for_artifacts["#{request.state}"] ||= []) << request.number
    end
  end

  def revoke_submit_requests
    submit_requests_with_same_target_and_source.each do |submit_request|
      next unless Pundit.authorize(@token.executor, submit_request, :revoke_request?)

      submit_request.change_state(newstate: 'revoked', comment: "Revoke as #{workflow_run.event_source_url} got closed")
      (@request_numbers_and_state_for_artifacts["#{submit_request.state}"] ||= []) << submit_request.number
    end
  end

  def submit_requests_with_same_target_and_source
    BsRequest.list({ project: step_instructions[:target_project],
                     source_project: step_instructions[:source_project],
                     package: step_instructions[:source_package],
                     types: 'submit', states: %w[new review declined] })
  end

  def source_package
    Package.get_by_project_and_name(source_project_name, source_package_name, follow_multibuild: true)
  end

  def source_package_revision
    source_package.rev
  end
end
