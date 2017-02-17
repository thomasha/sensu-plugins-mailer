#!/usr/bin/env ruby
#
# Sensu Handler: mailer-ses
#
# This handler formats alerts as mails and sends them off to a pre-defined recipient.
# Copyright 2013 github.com/foomatty
# Copyright 2012 Pal-Kristian Hamre (https://github.com/pkhamre | http://twitter.com/pkhamre)
#
# Requires aws-ses gem 'gem install aws-ses'
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'sensu-handler'
require 'aws/ses'
require 'timeout'

class Mailer < Sensu::Handler
  option :json_config,
         description: 'Config Name',
         short: '-j JsonConfig',
         long: '--json_config JsonConfig',
         required: false,
         default: 'mailer-ses'

  def json_config
    @json_config ||= config[:json_config]
  end

  def short_name
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def action_to_string
    @event['action'].eql?('resolve') ? 'RESOLVED' : 'ALERT'
  end

  def handle
    params = {
      mail_to: settings[json_config]['mail_to'],
      mail_from: settings[json_config]['mail_from'],
      aws_access_key: settings[json_config]['aws_access_key'],
      aws_secret_key: settings[json_config]['aws_secret_key'],
      aws_ses_endpoint: settings[json_config]['aws_ses_endpoint'],
      subject_prefix: settings[json_config]['subject_prefix']
    }

    body = <<-BODY.gsub(/^ {14}/, '')
            #{@event['check']['output']}
            Host: #{@event['client']['name']}
            Timestamp: #{Time.at(@event['check']['issued'])}
            Address:  #{@event['client']['address']}
            Check Name:  #{@event['check']['name']}
            Command:  #{@event['check']['command']}
            Status:  #{@event['check']['status']}
            Occurrences:  #{@event['occurrences']}
          BODY
    prefix_subject = params[:subject_prefix] + ' ' if params[:subject_prefix]
    subject = "#{prefix_subject}#{action_to_string} - #{short_name}: #{@event['check']['notification']}"

    ses = AWS::SES::Base.new(
      access_key_id: params[:aws_access_key],
      secret_access_key: params[:aws_secret_key],
      server: params[:aws_ses_endpoint]
    )

    begin
      Timeout.timeout 10 do
        ses.send_email(
          to: params[:mail_to],
          source: params[:mail_from],
          subject: subject,
          text_body: body
        )

        puts 'mail -- sent alert for ' + short_name + ' to ' + params[:mail_to]
      end
    rescue Timeout::Error
      puts 'mail -- timed out while attempting to ' + @event['action'] + ' an incident -- ' + short_name
    end
  end
end
