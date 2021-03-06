require 'httpclient'

class SlackListener < Redmine::Hook::Listener
	def controller_issues_new_after_save(context={})
		issue = context[:issue]

		channel = channel_for_project issue.project

		return unless channel

		msg = "#{escape issue.author} created #{escape issue.project} <#{object_url issue}|#{escape issue}>"

		attachment = {}
		#attachment[:text] = escape issue.description if issue.description
		#attachment[:fields] = [{
			#:title => I18n.t("field_status"),
			#:value => escape(issue.status.to_s),
			#:short => true
		#}, {
			#:title => I18n.t("field_priority"),
			#:value => escape(issue.priority.to_s),
			#:short => true
		#}, {
			#:title => I18n.t("field_assigned_to"),
			#:value => escape(issue.assigned_to.to_s),
			#:short => true
		#}]

		speak msg, channel, attachment
	end

	def controller_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		channel = channel_for_project issue.project

		return unless channel

		msg = "#{escape journal.user.to_s} updated #{escape issue.project} <#{object_url issue}|#{escape issue}>"

    extra = get_status_and_assignee_update_from_details(journal.details)
    msg += " (#{extra[:status]})" unless extra[:status].nil?
    msg += " assigned to #{extra[:assignee]}" unless extra[:assignee].nil?

		attachment = {}
		#attachment[:text] = escape journal.notes if journal.notes
		#attachment[:fields] = journal.details.map { |d| detail_to_field d }

		speak msg, channel, attachment
	end

	def speak(msg, channel, attachment=nil)
		url = Setting.plugin_redmine_slack[:slack_url]
		username = Setting.plugin_redmine_slack[:username]
		icon = Setting.plugin_redmine_slack[:icon]

		params = {
			:text => msg
		}

		params[:username] = username if username
		params[:channel] = channel if channel

		params[:attachments] = [attachment] if attachment

		if icon and not icon.empty?
			if icon.start_with? ':'
				params[:icon_emoji] = icon
			else
				params[:icon_url] = icon
			end
		end

		client = HTTPClient.new
		client.ssl_config.cert_store.set_default_paths
		client.post url, {:payload => params.to_json}
	end

private
	def escape(msg)
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		Rails.application.routes.url_for(obj.event_url({:host => Setting.host_name, :protocol => Setting.protocol}))
	end

	def channel_for_project(proj)
		return nil if proj.blank?

		cf = ProjectCustomField.find_by_name("Slack Channel")

		val = [
			(proj.custom_value_for(cf).value rescue nil),
			(channel_for_project proj.parent),
			Setting.plugin_redmine_slack[:channel],
		].find{|v| v.present?}

		if val.to_s.starts_with? '#'
			val
		else
			nil
		end
	end

	def get_status_and_assignee_update_from_details(details)
	  ret_status = nil
	  ret_assignee = nil
	  details.each do |detail|
      if detail.property == "cf"
        next
      elsif detail.property == "attachment"
        next
      else
        key = detail.prop_key.to_s.sub("_id", "")
        title = I18n.t "field_#{key}"
      end

      value = escape detail.value.to_s

      case key
      when "status"
        status = IssueStatus.find(detail.value) rescue nil
        value = escape status.to_s
        ret_status = value
      when "assigned_to"
        user = User.find(detail.value) rescue nil
        value = escape user.to_s
        ret_assignee = value
      end
    end

    return {:status => ret_status, :assignee => ret_assignee}
  end

	def detail_to_field(detail)
		if detail.property == "cf"
			key = CustomField.find(detail.prop_key).name rescue nil
			title = key
		elsif detail.property == "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
		else
			key = detail.prop_key.to_s.sub("_id", "")
			title = I18n.t "field_#{key}"
		end

		short = true
		value = escape detail.value.to_s

		case key
		when "title", "subject", "description"
			short = false
		when "tracker"
			tracker = Tracker.find(detail.value) rescue nil
			value = escape tracker.to_s
		when "project"
			project = Project.find(detail.value) rescue nil
			value = escape project.to_s
		when "status"
			status = IssueStatus.find(detail.value) rescue nil
			value = escape status.to_s
		when "priority"
			priority = IssuePriority.find(detail.value) rescue nil
			value = escape priority.to_s
		when "category"
			category = IssueCategory.find(detail.value) rescue nil
			value = escape category.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		when "attachment"
			attachment = Attachment.find(detail.prop_key) rescue nil
			value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
		when "parent"
			issue = Issue.find(detail.value) rescue nil
			value = "<#{object_url issue}|#{escape issue}>" if issue
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end
end
